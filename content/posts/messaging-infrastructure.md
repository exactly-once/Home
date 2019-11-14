# Messaging infrastructure

So far we've seen message de-duplication is not a simple topic and that *idempotency* is not a useful term then talking about distributed systems in which messages can get duplicated and reordered. Since we are sending our readers down the path of complexity we should at least discuss briefly what are the alternatives.

## Building blocks

In the model of a distributed system that was introduced in the previous posts, message processing can be broken down to a small set of simple building blocks. The set consists of five types of operations
- receive message
- execute business logic
- persist state change
- send outgoing messages
- consume the receive message 
It is the composition i.e. order and transaction boundaries, of these operations that define the properties of our system. 

Note that in the previous [post](/posts/sync-async-boundary) we've shown how these blocks have a slightly different shape at the system boundary. 

## Retries

Throughout this article we are assuming that the message queue we are using is durable and it re-delivers messages for processing in case previous processing attempts have failed. Receiving of a message is a read operation that has no side effects. In order to remove a message from the queue it needs to be consumed.

## Scope of a transaction

If two operations are combined into a transactions, it is guaranteed that either both operations complete successfully or neither is. This is the atomicity property of a transaction. Atomicity is not enough, though. We also need to make sure that the results of the transaction are not lost. In other words, we need these transactions to also be durable. That means that an operation can be transactional if it interacts with a medium that can durably record state. 

Let's see how the five operations of our basic building block can be combined to form transactions.

## No transactions

The trivial approach is to not use any transactions at all. In this case, we have three distinct failure modes:
- business logic has executed
- state change has been persisted
- outgoing messages have been sent
If we are sending out more than one message, the number of possible failure scenarios increases because sending each message constitutes a separate operation. 

This approach requires the least support from a technology perspective but is the hardest one to work with as the business logic needs to take into account all these failure modes and support deterministic behavior during retires.

## Atomic store-send-and-consume

At the opposite end of the spectrum we have the atomic store-send-and-consume mode, sometimes referred to as *fully-consistent*. In this mode a single atomic and durable transaction spans all the operations, excluding execution of the business logic. That probably comes as a surprise to you, doesn't it? The truth is, business logic cannot take part in the transaction because it is not durable as it only modifies the bit in the volatile memory of the computer.

The atomic store-send-and-consume mode is guaranteed to not generate duplicate messages in the course of the communication as the incoming message is consumed only if the outgoing messages are sent out, and vice versa. So, given there is no duplicate messages, does it mean this is equivalent to *exactly-once message delivery*? Not really. Exactly-once message delivery is impossible in our universe. The atomic store-send-and-consume mode is a different concept because of the fact that, as we stated above, the business logic is not transactional.

This means that if a message processing transaction is not completed and the message is delivered again, the business logic is executed as if it was the first attempt. If that business logic produces any side effects, these effects are produced for the second time. An example is calling a web service to authorize a credit card transaction. Each time a message processing is retried, a new authorization is created until the customer's balance reaches zero. We will deal with cases like this later in the series when we'll discuss various resources a system can interact with.

Atomic store-send-and-consume is a very powerful concept as it allows writing very simple business logic code. Provided that this code does not produce any side effects, the behavior of the system is exactly as if *exactly-once message delivery* was a thing. Sounds compelling, doesn't it?So how can I use this mode? The atomic store-send-and-consume can be implemented in two ways. 

First approach to use distributed transaction technology that ensures that individual transactions against the data store and the message queue are made atomic and durable. The problem is, such technology is no longer widely accessible. Few message queue products support distributed transactions and none of them is designed to work well in the cloud.

The second approach is to use a single technology for both storing data and sending messages or in other words, emulate a message queue in a database. The drawback of this approach is that databases usually are not designed with the type of workload that is characteristic to message queues, leading to poor performance compared to dedicated message queue solutions.

In summary, atomic store-send-and-consume is a great model from the simplicity of business logic perspective. Despite challenges related to technology, it should be always seriously considered when designing a distributed system.

## Atomic store-and-send

A commonly used middle ground between the two approaches described earlier is a mode called *atomic store-and-send* or *atomic store-and-publish*. In this mode there are two transactions
- persist state and send out messages
- consume incoming message
As a consequence, there is one partial failure mode possible when the state has been persisted and messages sent out but the incoming message has not been consumed. To handle that case the code of the service needs to be able to check if a given message has already been processed. 

You might now ask the question how can we implement a transaction that spans both persisting state and sending out messages. Wouldn't it require the same sort of infrastructure as the store-send-and-consume mode? As it turns out, it does not.

If the case of store-send-and-consume we are dealing with a problem that is equivalent to the distributed consensus problem. We need two parties (the database and the queue) to agree with the relation to committing the state changes and consuming the message. This category of problems is proved to not have a solution in an *asynchronous* network (one with no guarantees for eventual message delivery). In a more realistic model of *partially synchronous network* the problem of consensus fortunately does have solutions but they are both difficult and costly.

On the other hand the store-and-send is a much simpler problem of coordinating two operations in such a way that if one succeeds, the other will eventually succeed too. We'll lave the detailed discussion of that problem to the next post. Here it should be enough to state that storing outgoing messages in the database used for business data does solve the problem.

## Messaging infrastructure

The messaging infrastructure is the term we will use frequently in this series so let's define it now. The messaging infrastructure is all the components that are required to exchange messages between parts of business logic code. It necessarily consists of two parts. One of them is the message broker that manages the message queues (and possibly publishing topics). The other part, which is equally important, is the set of libraries that run in the same process as the business logic and expose the API for processing messages. 

## Summary

That was a nice piece of theory but you might ask yourself what's in it for me. Here's our suggestion. Choose your messaging infrastructure wisely. Avoid non-transactional infrastructure at all cost as it pushes the responsibility of handling all partial failure modes on the business code. This clearly violates the Single Responsibility Principle is a sure way to cluttered code. Using any message broker directly through its SDK it an example of non-transactional messaging infrastructure. Really.

The choice between atomic store-send-and-consume and store-and-send is a more difficult one. You need to take into account factors such as target deployment environment and expected performance. The good thing is that the decision is not that difficult to change, should the circumstances require it. If you are starting small, we recommend seriously considering *store-send-and-consume* and, only if it is not possible use *store-and-send*.

One last piece of advice -- before deciding to write your own messaging infrastructure code, seriously consider using an existing one. It will save you a lot of hassle. Regardless if take that advice seriously, stay with us as we explore various aspects of building *exactly-once message processing* solutions.

## Disclaimer

At the time of this writing the authors work for Particular Software, a company that makes NServiceBus. NServiceBus can be used with various message brokers like MSMQ, RabbitMQ, SQS and others to build messaging infrastructure that can work in either *store-send-and-consume* or *store-and-send* modes. NServiceBus is not the only product that offers similar capabilities. The authors point is not to sell NServiceBus but rather to turn your attention to a general issue. 




