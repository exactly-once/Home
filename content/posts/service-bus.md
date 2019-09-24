## Service Bus

Service Bus is undoubtedly an overloaded term so before we start discussing it, let's try to define it. For the purpose of this article we define the service bus as infrastructure that allows components of the software system to communicate (we call these communicating components services).

As we discussed previously (LINK), in a distributed system components are likely to communicate in the asynchronous way in order to minimize their temporal coupling. Therefore asynchronous communication is the first requirement for our service bus. 

You probably also remember that inter-process communication is necessarily either at-most-once or at-least-once in nature. We simply cannot guarantee exactly once message delivery through a network that can drop messages. As in most cases we can't afford to lose our messages, the only option is to live with at-least-once delivery and carry the burden of de-duplicating incoming messages. But wait! Wouldn't it be great if the service bus could do that for us? Let us see if we can make that happen.

Suppose we have our service bus in place. How our services are going to use it? Are all messages exchanged by these services essentially similar or can we see some distinct high-level patterns? In our experience time and again it proved to be useful to distinguish two types of messages, commands and events. Commands have a single destination service and that destination is known to the sending service. Events, on the other hand, can have multiple destinations and the publisher does not care who they are. In order for our service bus to be useful it has to support these two addressing modes.

## Ingredients

To build a service bus that satisfies all three requirements we need four basic ingredients. First, we need durable signalling i.e. a way to ensure that when a message is sent, it will eventually get to its destination. Note that we decouple here the signalling that a message needs to be processed from actually delivering the payload of the message. The latter forms a separate ingredient. The third ingredient is the de-duplication mechanism that needs to ensure exactly-once message processing by the destination service. The forth and last ingredient is the routing that allows event type messages to be subscribed to and published.

## Signalling

The simplest technology that provides signalling capability in Azure is Storage Queues (the AWS equivalent is SQS). The Storage Queues offer high throughput and low cost-per-message. The downside is a very strict limit on the size of a single message. This is why payload delivery needs to be a separate concept.

## Payload delivery

The natural solution for payload delivery in Azure is the Blob Storage (the AWS equivalent is S3). Blog Storage biggest advantages is price and the practical lack of size restrictions for the stored objects (in fact there are restrictions but they are high enough that we can ignore them, at least for the purpose of building a service bus).

## De-duplicating

The durable signalling mechanism works, by definition, in the at-least-once mode. This means that the receiver can get multiple signal messages for each sent message. How can we ensure that the receiver can discard the duplicates?

First, we need to ensure we can tell if a message is a duplicate or not. As we discussed [earlier](https://exactly-once.github.io/posts/consistent-messaging/) we need to assign each message a unique ID. Let's now take a look at behavior of a simple service that receives a message, changes its state and sends out another message.

### Knock, knock! Who's there? A message!

A message comes in. How does the service tell if it is a duplicate? Previously when discussing the Inbox/Outbox pattern (LINK) we've seen that we can use a key-value store (or similar structure) to keep track of processed messages. If a given ID is in the store it means that it has been processed. As you remember, the downside of that approach is lack of deterministic retention strategy for the Inbox. There is no way to tell with absolute certainty when a given Inbox entry can be evicted and without eviction the Inbox would keep growing forever. Previously we accepted that limitation but now it is time to challenge it.

### Inbox, upside down

Let's invert the way the Inbox works. Instead of keeping track of processed messages, we are going to keep track of unprocessed messages. This way we can keep the Inbox size stable and equal to number of in-flight messages. How would that work? The sender of a message needs to create an inbox entry before sending the message. Then, it sends a signal via the signalling mechanism. Upon receiving the signal, the receiver checks if the inbox entry exists. If so then it processes the message and deletes the inbox entry. Otherwise the message is considered a duplicate and ignored.

At first this approach looks correct but in fact has one serious flow. Can you spot it? There is a race condition between deleting an inbox entry and checking its existence. If two copies of a given message arrive at the same time, both will pass the inbox entry check and the message will be processed two times. Not good.

### Outbox

Fortunately we already know a solution for that: the Outbox (LINK). All we need is an entity in the receiver's data store that represents a message while it is being processed. Of course that entity needs to be operated in the same transaction as the business data. 

Coming back to our message. The service checks if an inbox entry for the message it has just received exists. If it does, the service can assume, with high likelihood, that the message has not yet been processed. Based on this assumption, the service executes the business logic and persists the state change to the data store. Within the same transaction it attempts to create the Outbox record that represents the incoming message. If another thread has, in the meantime, processed a different copy of the same message, storing the outbox record would fail and the transaction, as a whole, would be rolled back. Fortunately that did not happen and now we can proceed to deleting the inbox record. That was easy. Now that the inbox record no longer exists (and therefore no other thread can begin executing the business logic for this message) we can finally get rid of the outbox record.

### Race conditions, again

All good? Unfortunately there is still a race condition. Can you find it? Here is a scenario that breaks the algorithm. Two copies of a single message arrive. The first copy is processed successfully but the inbox record is not deleted yet. In this very instant the second copy is picked up and the code checks if the inbox record exists. It sill does so the thread that processes the second copy starts to execute the business logic. Worst case it will fail while persisting the Outbox record, right? Unfortunately not, because in the meantime the first thread manages to delete the inbox record and immediately gets rid of the outbox record too. The second thread commits its processing transaction uninterrupted violating the exactly-once semantics. What did go wrong?

Clearly checking the existence of the inbox record does not provide us with strong enough guarantee as it allows creating multiple outbox records for the same message. We need something better. We need a way exclusively claim the inbox record for a given outbox record.

### Claim

The added *claim* step is executed after creating the Outbox record but before attempting to execute the business logic. Each Outbox record, when created, is assigned a unique Claim ID. When claiming the Inbox record, this Claim ID is stored in the Inbox record. The processing of a given outbox record can proceed only if an Inbox record exists and has the same Claim ID. If the Inbox record does not exist or is already claimed by other Outbox record, the message is ignored as a duplicate.

There is still one catch here. The algorithm only works if we can guarantee that a given inbox record can be claimed only once. Simple update is not enough as the second thread would simply overwrite the Claim ID of the first one and we would be back in square one. In order for claiming to work correctly the operation need to be conditional: *set ClaimID if it has not been set yet*. In other words, claiming has to be implemented as a [compare-and-swap](https://en.wikipedia.org/wiki/Compare-and-swap) operation.

This small, but very significant, change finally ensures exactly once processing. What technology in the cloud supports CAS and can be used for the inbox? Again, Blob Storage seems to be a good fit. It provides CAS-like semantics via `If-Match` header.

### Sending outgoing messages

Are we done yet? Unfortunately not. What if the receiver needs to send its own messages? As we discussed in the [Outbox](LINK) article, in order to guarantee deterministic message sending, the outgoing messages need to be persisted in the same transaction as the business data state change. But persisting them is not enough. To actually send them we need to add two more steps between claiming the Inbox record and deleting the Outbox one. 

### Creating Inbox Records

The first step is to ensure each outgoing message has an associated Inbox record. To do so we iterate over all outgoing messages stored in the Outbox record and, one by one, create the Inbox records. Each inbox record is assigned the key equal to message ID. Once all the inbox records are created we can start sending them. As mentioned above, sending a message is a two-step operation that consists of storing the payload (Blob Storage) and signalling (Storage Queues).

At this point you should suspect that something is still off. And you would be right. The Inbox record creation is not as simple as it seems. Let's examine the following scenario. A service is going to finalize processing a message `A` which generated an outgoing message `B`. The Outbox processing code attempts to create an Inbox record for key `B`. Unfortunately the request it sent to the Blob Storage is lost somewhere between the network routers. The receive operation times out and the message `A` gets back to the queue. As it is picked up again, the service recognizes that the business logic has already been executed and all it is left to do is to create the Inbox records and send the messages. This time it works correctly.

Message `B` is received by some other service that manages to process it successfully. Unfortunately, for some random reason, it fails to acknowledge the signal message with Storage Queues. The `B` message gets back to the queue. At the same time the network packets that carried the first Inbox create attempt for message `B` are miraculously recovered and forwarded to the Blob Storage a millisecond before the signal for message `B` is picked up. Outcome? The message `B` is processed twice. How we fix it?

We need to ensure that only successful attempts to create an Inbox record valid for the purposes of de-duplication. Let us add yet another ID, the Attempt ID. The attempt ID is not stable and persistent (as message ID is) but generated just before creating an Inbox record and used a key for the record. The signal message carries both IDs. When the sending service re-attempts to generate Inbox records, it uses different attempt IDs, rendering potential previous Inbox create attempts invalid. In other words the sending service needs to ensure that the Inbox records are created using at-most-once approach.

### Sending out messages

That was the first step. Now the second step. You might be disappointed to hear that there is no hidden problems here. The only thing we need to make sure is that the Attempt IDs for the last successful attempt to create Inbox records are persisted in the Outbox record before proceeding to sending out messages. Why? We'll leave that question as a homework for the reader.

### Outbox, revisited

Now that we killed all the race conditions let us sit back, relax, and think about the Outbox. As we stated multiple times, the requirement is that the Outbox record is modified in one atomic operation with the business data. That sounds like we have some serious limitation regarding the technologies we can use for the business data storage.

In fact that is not true. As we discussed in the previous article [LINK], the Outbox can be implemented over various different storages. Recall the article about the types of resources a service can interact with? The Outbox can be implemented over any resource that either allows metadata storage or offers cross-entity transactions. Examples include, but are not limited to, Azure Table Storage, Cosmos DB, Azure Blob Storage (provided it is used as document database for storing json files), any relational database and many more.

More importantly, since the Outbox is not exposed outside of a given service, different services are free to use whatever technology they see fit for the outbox. A service that uses Table Storage can freely communicate with another one that uses a SQL Azure database as long as both use the same signalling and payload storage components.

## Publishing

The last ingredient we need is a mechanism to publish messages. Our signalling and de-duplication mechanisms are inherently point-to-point. Not only each recipient needs to receive a separate signal but it also requires its own separate inbox entry. For the sake of simplicity we could also assume that each recipient gets its own message payload entry. We will left for the reader an exercise to design a message payload mechanism that allows sharing payload entries.

A simple publishing mechanism consists of map that associates topics with recipients. When a given recipient wants to receive events for a given topic, it associates its name with the topic. Of course multiple recipients can be be associated with a single topic at any given time. Here, again, the Blob Storage seems to be adequate technology. Each topic can be represented as a json file that contains a list of recipients.

When publishing a message, the publisher reads the contents of the topic file and executes turns the publish operation into a series of send operations, one for each subscriber. This pattern is known as [recipient list](EIP).

## Putting it all together

Now that we have all the ingredients, let's try to put them together. The first thing that worth noting is the fact that the service bus we built seems to follow the *smart endpoints, dumb pipes* approach that is widely considered the best practice for building infrastructure for distributed systems. The pipes in our case consists from Storage Queues and Blob Storage. All the smarts are concentrated in the endpoints where the Outbox/Inbox processing logic is executed. Each endpoint has access to its own storage where both the Outbox records and business data is persisted.
