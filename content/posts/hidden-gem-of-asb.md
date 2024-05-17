# The hidden gem of Azure ServiceBus

The Azure ServiceBus is by far the most advanced cloud-native messaging solution available today. It boasts a host of advanced features in the areas of routing, high availability, communication patterns and others.

Today we are going to focus on one of the least well understood features of Azure ServiceBus -- the [ability to atomically consume and send messages](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-transactions#transfers-and-send-via) referred to also as *send via* or *transfers*. As far as we know, this feature is unique among all messaging platforms available in the cloud.

The *send via* works as the name implies: it allows to send a message to queue `B` while consuming a message from queue `A`. Because the message to `B` is *sent via* `A`, both operations can be made atomic by the underlying infrastructure.

## Eureka?

Now you might be wondering why do we even write about it. The trigger for this blog post was a question we got during our workshop at [dotnetdays.ro](https://dotnetdays.ro/):

> What is the benefit of the Azure ServiceBus' atomic-consume-and-send mode (*send via*)?

Our best answer, at that moment, was a quite confident "pretty much none". Most non-trivial message processing logic involves some modification of persistent state (also known as database) and there is no clear benefit of *send via* in these scenarios. To guard against duplicate processing we still need to employ the outbox pattern. You might be now asking why? Doesnt atomic-consume-and-send prevent duplicates? Well, it does prevent duplicates at the sending end but duplicate processing of a single copy of a message can still happen.

The reason for that is the fact that there is always inter-process communication involved when talking to a messaging infrastructure and that communication can be interrupted for any reason. If that happens, the infrastructure has two choices: wait until the connection is re-established and ask about the state of the message or hand the message over to another instance of the processor. The former option is problematic because the original processor may never come back online. What if that happens? For all intents and purposes the message is not lost. We are not aware of any message queue that uses this approach. That forces us to always consider a possibility in which multipe processes race to handle a given message.

Back to our story from the workshops. We have discussed various deduplication strategies for the whole two days and concluded that the Outbox pattern, despite having some significant challenges, is the best available solution. 

## The goal

Back home we continued to ponder the idea of *send via*. We had a hunch that our answer was wrong but we were not yet sure what is the correct one. We decided to examine how employing the atomic-consume-and-send mode would affect the well-known outbox implementation. Out hunch was that if we can manage to successfully bend the outbox pattern to take advantage of the *send via*, we would be able to remove the biggest issue of that pattern, namely the need for storing and managing the deduplication information. That seemed to be something worth trying out. We decided to take a step-by-step approach, chaging one thing and looking at what has broken.

## Marking messages as dispatched

The classic outbox algoritm marks outgoing messages as successfully dispatched to their destinations immediately after finishing all the queue API calls. At this point we can safely say that the messages are durably stored in the messaging infrastructure and we can remove them from the outbox record.

That is not the case when using atomic-consume-and-send mode because the consume-send transaction can still fail later when trying to acknowledge the incoming message. In this case all the sends we have done are rolled back and the incoming message is returned to the queue. We get another chance to dispatch the messages we generated but for that we need the message payloads to still be in the outbox record.

The solution is to include a special control message in the send batch. That message is destined to the endpoint's own input queue and carries only the ID of the outbox record. By virtue of it being part of the consume-send transaction, when it arrives we know for sure that the consume-send transaction has committed and we can now safely mark the outbox record as dispatched. With that change we have an approach that is guaranteed to not produce duplicate messages on the sender side and we can take advantage of it by changing the implementation of marking as dispatched from `UPDATE` to `DELETE`. In the original outbox at this point we remove the outgoing messages but we keep the record for deduplication purposes. Assuming the messaging infrastructure is robust and does not introduce duplicates by itself, we can change that behavior to deleting the whole record. No more need for managing huge outbox tables. The problem is solved and we are done, right? It turns out that not yet.

## Slow is your enemy

While we believe modelling with TLA+ is by far the best way to ensure correctness of deduplicatio algorithms, simply thinking about what can go wrong when one of the processes gets paused in an arbitrary place is still very useful. Let's use that technique now to uncover a weak point in our approach. 

Imagine the following situation. One process receives but immediately after receiving it is paused. Maybe the OS decided that it needs to dump some memory pages to disk or the runtime wants to perform a really thourough garbage collection. Whatever the reason, the process is frozen. After some 30-or-so seconds the messaging infrastructure becomes impatient. Eventually it gives up waiting and decideds to give the message to another process. Here you go, process two!

The way various messaging infrastructures handle this part differs so we'll focus on one of the most popular ones, Azure ServiceBus. The way it does the hand-over is by generating a new lease token and giving it to the other process. At the same time, the old lease token becomes invalid. Azure ServiceBus consume process is based on leases, not transactions. The queue ensures that only the process that presents a valid lease token can consume the message.

Back to our story, the second process goes on to handle the message. It executes the business logic that generates the follow-up messages and modifies the state in the database. Uninterrupted, it commits the outbox transaction and immediately attempts to dispatch the outgoing messages. After that is done, it attempts to consume the incoming message presenting the lease token it got with the message. Azure ServiceBus checks the token and allows the transaction to commit. At this point the contol message we mentioned in the previous section is also released, received, and finally processed, resulting in removal of outbox record. No sign of that message is present in the system anywhere.

At that very moment the first process wakes up ready to do some work. It has a message to process, doesn't it? Unfortunately it does not know that the message it got has already been processed and the lease token it holds is no longer valid. Ignorant of that, it attempts to execute the business logic and commit the outbox transaction, storing both the generated messages and changing the state of the database. It does so without any problems because no deduplication information exists any more. Next, it tries to dispatch the outgoing messages and commit the transaction. That operation fails as the lease token is rejected by the Azure ServiceBus. Result? The database has been modified twice. Not good.

##  Check twice, commit once

A well-known advice for any type of woodworking is to *measure twice, cut once*. Let's try to use that advice here. The problem we described above stemmed from the fact that the paused process committed its outbox transaction while it did not hold a valid lease token. We need to find a way to prevent that from happening. Fortunately, Azure ServiceBus offers an API that can do just that. Well, actually it does something a bit different but it is close enough. The API allows a process to prolong the lease on a message is called [Renew-Lock](https://learn.microsoft.com/en-us/rest/api/servicebus/renew-lock-for-a-message). If it succeeds, the caller knows it still holds a valid lease. Otherwise it knows the lease is not good any more and it should not proceeed with committing the outbox transaction.

We can now insert the `Renew-Lock` call right before the commit to solve our issue. But have we really solved it? Using the *slow is your enemy* technique again we can show that what we really achieved is moving the problem elsewhere. In this case, a well placed long pause between the call to `Renew-Lock` and committing the outbox transaction causes the duplicate update. It is true that by doing this change we made the problem less likely, but that is not good enough for us. Back to the drawing board.

What we did so far was an eqivalent of measuring once. Now let's really really follow the advice. The solution to a race condition like this one is to use optimistic concurrency. So far we assumed the outbox transaction is simply an insert. Inserts have this property that they always succeed if there is no primary key conflict. What if we switched to using updates instead?

Let's break down the outbox transaction into two operations:
 - `INSERT` that stores an empty record with just the message ID as a primary key or `SELECT` that loads an empty outbox record if one alreay exists
 - `UPDATE` that stores the outgoing messages. Is guared with an optimistic concurrency clause. It only succeeds if an outbox record exists and is empty.

That change by itself does not give us any advantage. In fact it could be done to any outbox implementation without changing the behavior. The key here is that we place the `Renew-Lock` call between the `INSERT/SELECT` and the `UPDATE`. That means that the outbox transaction can be committed (by successfully executing the `UPDATE`) only by a process that was able to validate the lease while holding the *optimistic concurrency right* to do the `UPDATE`. If either of these is no longer true i.e. another process has committed the outbox transaction or the lease token has been invalidated, commit is prevented. With that change there is no way we can place an arbitrarily long pause to cause the algorithm to fail.

Note, that if the data source we deal with is not a relational database but rather a document or key-value store, the optimistic concurrency check we added by splitting the outbox commit into `INSERT` and `UPDATE` is likely already built into our data access pattern. In our previous post on [improving the outbox](https://exactly-once.github.io/posts/improving-outbox/) we explain why it is so critical to load the entity we operate on before checking the external store for duplicates.

## Conclusion

The atomic-consume-and-send mode of Azure ServiceBus implemented using *send via* allows us to use a modified outbox algorithm that does not require storing deduplication data beyond the duration of the transaction. That is a very significant advantage over the classic outbox implementation. We can't overemphesise how excited we are about the improvements it offers.

A point worth noting is the similarify with the [token-based approach](https://exactly-once.github.io/posts/token-based-deduplication/). One of the key aspects of that approach was the idea of claiming the token **while holding the optimistic concurrency right to update the outbox record**. The equivalent in the atomic-consume-and-send outbox is the `Renew-Lock` API call. That means that you can think about the lease as a token generated and managed by the Azure ServiceBus and, in fact, it is exactly that. The token-based deduplication approach is in fact re-implementing the lease-based atomic-consume-and-send built into Azure ServiceBus for message infrastructures that do not offer that high transaction guarantees.
