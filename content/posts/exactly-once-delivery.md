# Exactly-once message delivery

It is widely known that exactly-once message delivery is impossible in any distributed system. But what exactly is exactly-once delivery? To answer that question we need to first ask what do we understand as message delivery. This is not an easy task. The receiving system is not a single blob of code. It consists of multiple layers. Is the message considered "delivered" when all its bytes are read from the network cable? If not then maybe when the message is passed to the application? Or maybe when the application completes the procedure that acted on the data? Finally, maybe we should consider a message delivered when the TCP connection is was received on is closed?

As odd as the last option might sound, this is the only option in which the sender application can be sure that the receiver got the message. As you can see, the term "message delivery" can be confusing. This is why throughout this series of blog post we used the term "message processing" instead. The has much more clear semantics. A message is processed when all side-effects of the procedure used to handle that message are durably persisted.

Based on that we can establish some derived terms. *At-most-once* message processing means that for each message sent, the side effects of its processing may either be missing or applied once. In contrast *at-least-once* message processing means that the side effects ma be applied multiple times but they may never be skipped. Finally, exactly-once message processing means that the side effects are guaranteed to be applied once.

### How

Contrary to a popular opinion, *exactly-once* message processing as defined above it possible in real world. It is really unfortunate that the Internet is full of claims according to which *exactly-once delivery* is impossible because of the so-called [two-generals problem](https://en.wikipedia.org/wiki/Two_Generals%27_Problem). What that problem *really* illustrates is that *consensus* is impossible in the asynchronous network in which arbitrary message loss is possible. So let's focus on the problem at hand. How do we achieve *exactly-once* message processing in a real-life distributed system?

### Layers

The concept of layer is very useful when describing software systems. Layers allow us to contain the complexity of solving certain class of problems while exposing simple abstractions to the layers above. We will now look at ways of providing *exactly-once* processing guarantees working our way up the stack from the lowest layers to the highest.

### Message queue

The most basic way for two processes can communicate is to send sequences of bytes to each other directly. For the sake of clarity in this article we will use a different model in which processes send messages via a *message queue*. All we need to know about the *queue* is that it can durably store messages and allows retrieving messages in First-In, First-Out (FIFO) order.

### Transactions

When we defined message processing the key concept we used was durable persistence of side effects. We did not specify, though, how and where these side effects are persisted. These side effects come in two flavours. First, they include changes in the data store used by the receiving process to store its state. Second, the side effects are also all the messages sent out as a result of processing the incoming messages.

In order to guarantee *exactly-once* processing we can use the transactions that include three operations:
 - take a message off the queue
 - modify the state
 - enqueue resulting messages

Transactions guarantee that included operations are atomic and durable. That means that either all three operations are completed or none is. Also, once a transaction is accepted by a system, the system guarantees it won't disappear in future. Transactions are implemented using a concept of a log -- an ordered sequence of operations stored on disk. When transaction is submitted, its description is first written to a log. Only after the log is made durable (e.g. by writing a checksum and ensuring that all write buffers are flushed) are the operations actually applied to the data.

You probably now can come up with at least one transactional store that can be used to build an *exactly-once* messaging system. Most people think about relational databases. These systems offer very flexibly support for transactions that can span multiple rows, multiple tables and, in some cases, even multiple databases (on the same instance). Relational databases are also very flexible in the way you can define the structure of the data which means queues can be implemented inside such a database.

So next time you see a system that uses e.g. NServiceBus SQL Server transport you'll know that it works because the underlying transaction log guarantees atomicity of the receive-update-send operation.

### Distributed transactions / consensus

It is not always possible or desirable to use the same transactional storage to serve both as data store and message queue. Queues implemented in a relational database can never match the throughput of native queuing solutions. As a result we may be forced to use two different technologies. How do we ensure *exactly-once* message processing in this case?

One option is to extend the concept of transaction. If transaction within one resource are useful, surely transactions that span multiple resources would be even more useful. At least that's what people thought in the early 80s when they came up with the concept of distributed transactions. Here we meet our two generals again. Remember? We mentioned that the two-generals problem shows that distributed consensus is not possible. Well, if it is not possible then how do people claim it works? It turns out the impossibility proof is based on the assumption of an asynchronous network in which messages may be delayed arbitrarily long. In such a network no consensus algorithm can guarantee progress. Fortunately real-world networks are not asynchronous. They are more like *semi-asynchronous networks* and that means that messages are delivered eventually. This seemingly weak guarantee is enough to allow a number of consensus algorithms to be proven reliable (e.g. Paxos and Raft).

So what is that consensus and how does it work? It can be defined in a number of ways but for our purposes it means that for each transaction two (or more) nodes of a system agree that is has been accepted or rejected. There are two widely known types of consensus algorithms. One type is represented by Paxos and Raft we mentioned before. These algorithms are used by distributed databases to ensure data consistency across nodes. The other type is represented by the infamous [Two-Phase Commit](https://exactly-once.github.io/posts/notes-on-2pc/) (sometimes referred to as 2PC). These algorithms are meant to coordinate transactions between different data stores. For the purpose of *exactly-once* delivery this second type is more useful. We'll explain it using the implementation provided by Microsoft in form of Distributed Transactions Coordinator (DTC) service.

Both MSMQ (a queuing system built-into Windows) and SQL Server support 2PC protocol implemented by DTC. When the receiver takes the message off the queue, it does so in the context of a distributed transactions managed by the DTC. It uses the same transaction context to modify the state in the database and to send outgoing messages. The result is (almost) exactly the same as when using local transactions. There are some differences, though. The main one is related to visibility, which is not defined in the 2PC protocol. While in local ACID transactions all changes are made visible at the same time, in distributed transactions each participant makes the changes visible individually. As a result, you may run into situation in which an outgoing message is sent and received before the change of state in the database is visible. This may be confusing for downstream message processors.

It widely known that 2PC protocol is not "bullet-proof". It cannot reliably recover from a failure of both the coordinator and a participant. While in practice this problem is very rare, it makes many people stay away from 2PC. 

### Broker protocol

So far we assumed that the message queue is a very simple entity. It does not have to be that simple, however. We will call a smarter variant of a message queue a message *broker*. If using a single data store or distributed transactions is not an option, the next layer we can guarantee *exactly-once* message processing is the endpoint-to-broker communication protocol.

Let's imagine a protocol that offers an abstraction of a *link* which is a unidirectional communication channel over which messages can be send. Each message has a unique ID. We can associate a state with a link on both sides of the connection. Each side, the sender and the receiver, keeps track of messages it sent/received. When the sender transfers a messages, it marks its ID as *sent* in its link state. When the receiver receives the message, it marks it as *received* and sends a confirmation to the the sender. When the sender gets the confirmation, it can finally erase that message and dispatch another confirmation to the receiver. Upon receiving that confirmation the receiver can forget about this message as it now knows that the sender will never re-attempt to transfer it. Such a protocol can be used to reliably transfer messages from one message store to another e.g. between nodes of a distributed messaging system.

How can we adopt it to ensure *exactly-once* message processing? All we need to do it build an implementation in which the link state is stored atomically with the application state.

You might now think that we are talking about abstract things but that's not true. In fact the description above explains how the widely adopted [AMQP](https://www.amqp.org/resources/specifications) protocol works. There is caveat, though. At the time of this writing we are not aware of any implementation of the AMQP broker that support durable link state and link state recovery.

### Application framework

What if we are unlucky and we can't rely neither on transactions nor on the protocol support from the broker? It turns out we can still build *exactly-once* message processing system by implementing the required mechanics in the application framework that is use case-agnostic.

Most known application frameworks use a variant of the [Outbox](https://exactly-once.github.io/posts/outbox/) pattern. In the most simple implementation an outbox *record* is used to associate the ID of the incoming messages with the list of the resulting messages. The outbox *record* is created in the same atomic transaction that the application state is updated. This guarantees that duplicate messages are detected and ignored.

The big challenge in implementing the application framework approach is eviction of the old outbox *records*. In the simplest version an age-based eviction can be used but that does not provide bullet-proof guarantees. Deterministic eviction mechanism similar to AMQP's double acknowledgements are possible but are quite complex.

### Application code

Next layer up the stack, the *exactly-once* message processing can be implemented in the application code itself. 

TBD

### Message broker

Finally the message broker itself. [Many message brokers claim](https://aws.amazon.com/about-aws/whats-new/2016/11/amazon-sqs-introduces-fifo-queues-with-exactly-once-processing-and-lower-prices-for-standard-queues/) to support *exactly-once* message processing to some degree. Unfortunately this is very confusing as the message broker is precisely the place where *exactly-once* message processing cannot be implemented. 

What we wanted to prove in this article is that *exactly-once* processing necessarily requires some form of participation from the message processing endpoint. This participation may be in form of using a shared data store, taking part in distributed transactions or implementing a protocol. So next time you see another messaging infrastructure vendor claiming you'll get *exactly-once* message processing magically if only you sign that contract, you know what to reply.

### Future

TBD
