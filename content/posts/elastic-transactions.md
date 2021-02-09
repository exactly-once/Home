# Elastic transactions to the rescue

One of the fairly new features of Azure is the Elastic Transactions. It is a new addition to the SQL Azure offering that allows executing atomic transactions that span multiple SQL Azure instances. Why is that important? In one of the previous posts we looked closer at the 2PC protocol and tried to debunk some of the myths that surround it. We showed that it can indeed be useful in some contexts. Let's see how we can use that newly acquired knowledge in practice.

## A queue in a database

Implementing a queue using a database table is an age-old pattern. In the SQL Server world it became practical with the advent of the so-called *destructive select* statement that can both remove a row and return its contents to the client (for those of you who are curious, the *destructive select* is in fact a `delete` followed by an `output` clause). 

The idea is very simple. We define a table that contains two columns, the `Sequence` and the `Payload`. The former is an auto-incremented integer value that defines the order of items in the queue. The latter is the actual message serialized using your favourite serialiation method. To enqueue a message you simply need to `insert` a row that contains the payload. Processing messages is only slightly more complicated. You need to use that *destructive select* mentioned earlier but you also need to ensure that the dequeued row is locked and that the `delete` is going to skip over (based on the `readpast` query hint) any already locked rows. Why is that important? Imagine a multi-threaded receiver which tries to execute the receive in both threads simultaneously. If not for the `readpast` clause, one of the attempts would be blocked waiting for the other to finish. With `readpast` multiple threads can simultaneously poll the queue for outstanding messages without stepping into each other's toes. Sounds too good to be true, right? Beware of the dragons ahead.

## Index

In order to enforce the FIFO behavior of the queue the *destructive select* has to use the `Sequence` column in the `order by` clause. That means that we need an index. The problem is going to be modified with each `insert` and `delete`. This puts a lot of stress on the database engine and might be the source of the dreaded *dead locks*, even though no queries lock the same data rows. In this case the deadlocks are caused by concurrent access to the index pages.

## Polling

Unfortunately the database does not provide any reasonable way of notifying the user code about the new rows getting added to the table. The receiver needs to periodically attempt the *destructive select* to check if there is anything to receive. That polling does not cause any overhead if the table contains data. You might expect that this should be the case most of the time. Unfortunately that's not how statistics works. Queueing systems are most likely to be in one of two states: empty or full. Continuous polling of an empty queue adds significant pressure on the database engine.

## Payload

Relational databases are really good in handling small pieces of data. Not so good in handling large blobs, especially if these blobs are short-lived -- deleted seconds after they are created. Although the database server can cope with that kind of load, it is not designed for that. It results in generating huge numbers of data pages that need to be recycled. For a custom database server deployed on-premise it would not be a big deal as these servers are usually anyway over-provisioned. For a cloud SQL service such as SQL Azure, using it a blob storage directly translates to much higher monthly bills.

## A better queue

Now that we examined the pitfalls of a naïve implementation of a queue in a database let's see if we can do better, provided that we have access to all the cloud services of Azure.

## Payload

The simplest change is to off-load the message payload to the Azure Blob Storage. The change required is minimal. Implementing it will, of course, make each individual message processing take slightly longer as now we need to contact both the SQL database and the Blob Storage. What we gain, though, is throughput. The same instance of the SQL Azure database can now handle much more messages.

## Polling

Now it is time to address the issue of polling. We can replace it with some sort of a notification service by which the sender would ping the receiver when there are messages to be received. The Storage Queues (ASQ) seem to be ideal solution as they are relatively inexpensive. Note that we don't need to send notification after each produced messages. There is a trade-off to be made between latency and cost. The higher the notification frequency, the lower the latency of communication but the cost is higher as we use more messages. Higher notification frequency would also impact the sender's performance as it needs to send more ASQ messages.

A big advantage of ASQ over plain HTTP as a notification service is the fact that the receiver of the notifications does not have to expose any communication ports. This is a benefit from the security point of view.

## Index

The updatable index is the last problem we are going to tackle. Can we come up with a table design that does not require index updates when sending and receiving? This rules out inserts so we need a data structure that has a fixed size but has the FIFO semantics, just like a queue. A good candidate solution is a circular (or ring) buffer. 

A circular buffer consists of a fixed number of cells that are labeled from `1` to `N`. Each cell has a flag that informs if the cell contains data. The writer starts writing entries from position `1`. As data is written, the flag is set to `true`. The reader, similarly, starts reading from position `1`. It continues reading as long as the next cell has the flag set to `true`. If not, it stops and waits for the writer. When the reader reads the cell, it sets the flag to `false`.

When the writer writes an entry at position `N`, it returns back to `1` and continues writing as long as cells have their flag set to `false`. When the writer reaches a cell with flag set to `true`, it stops. I cannot overwrite the data because the reader didn't process it yet.

This means that, unlike a naïve queue, the circular buffer can refuse to enqueue messages when it is full. Is that a problem? It seems so at the first glance but in fact we would argue that the circular buffer design is better than the queue. The fact that the queue does not have a limited size is actually a big drawback as the system is *unbounded*. 

If the rate of the data coming to the system exceeds the throughput of the slowest component, the queue in front of that component would continue to grow until it uses up the entire capacity of the underlying storage device. Assuming that the storage device is shared between multiple queues (which is almost always the case), at that point the whole system collapses.

When using bounded buffers, if the rate of the incoming data exceeds throughput of one of the processors, its buffer would get full and, as a result, the processor upstream from the bottleneck would not be able to process its messages. That processor's buffer would get full, causing the one upstream to stop processing messages. You can spot the pattern here, right? If the problem is not resolved in time, the whole path from the system boundary to the bottleneck would be blocked and the boundary component would be forced to drop messages on the floor. This is not ideal but the good thing is the other parts of the system would not be affected at all.

## Back to elastic transactions

You might now wonder how does it relate to Elastic Transactions. Here's the answer. Elastic Transactions allow atomic modifications of more than one database. One of these databases can contain the business data of a microservice while the other might be used to store the circular buffers for the system's queues. The queue database would be linked to all the microservice database via Elastic Transaction links.

This means that service A can modify its state and send a message to service B atomically. Either both succeed or none does. No duplicates and no message loss. On the other side service B can receive a message and modify its own state, also atomically. Again, no duplicates possible.

While it remains true that message ID-based de-duplication is the best solution for loosely coupled components, Elastic Transactions combined with smart circular buffer design can be very helpful when communicating between tightly- or moderately-coupled services.
