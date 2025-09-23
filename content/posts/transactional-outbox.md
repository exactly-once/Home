# Abstract

The outbox pattern is the most common approach to ensuring consistency of data in distributed software systems that use durable asynchronous messaging as the communication mechanism. It stores the outgoing messages in a database alongside business-specific data (atomically with business state transition) and later attempts to push them out to their destinations. The stored messages are usually tagged with the ID of the incoming message that triggered the processing in order to allow de-duplication as the save-and-push mechanism inherently generates duplicates in cases of intermitent failures. The downside of this mechanism is that for correctness, it requires keeping the de-duplication information in the database (ideally forever, but for practical purposes for weeks). Removal of stale de-duplication data creates significant pressure on the data store, resulting in unpredicable transaction performance and frequent deadlocks. This article explores a modified outbox pattern that takes advantage of properties of certain durable asynchronous messaging infrastructures to eliminate the need for keeping the de-duplication data.

# Content

## Durable asynchronous messaging

Durable asynchronous messaging is a communication mechanism used frequently in distributed business software to ensure the system is robust in face of failures of individual components. The approach requires specialized piece of infrastructure (known as _messaging infrastructure_) that allows components of the system to send and receive messages. The key difference between direct component-to-component communication is the fact that the _messaging infrastructure_ durably stores the message in transit. Once a message has been _acknowledged_ by the _infrastructure_, the sending component can be sure that it will _eventually_ get delivered to the receiving component. 

The messages are usually delivered to receivers in the _First In-First Out_ so _messaging infrastructure_ is often referred to as _message queue_ or simply _queue_.

The _messaging infratructure_ re-tries message delivery until the receiving component _acknowledges_ processing the message. In order to guarantee message processing in face of failures of the receiver, the _messaging infrastructure_ usually uses _lease_ mechanism to detect receiver failure. Each message is delivered as a _lease_ and once the _lease period_ expires, the receiver is considered failed and the _infrastructure_ generates a new _lease_ and delivers the message again. Some _messaging infrastructures_ expose APIs allowing to extend the _lease period_ if the receiver is aware that the processing may take longer than usually.

The basic operations exposed by _messaging infrastructures_ are usually:
 - `Send` - send a message
 - `Receive` - receives the next message in the queue as a _lease_
 - `Consume` - acknowledges processing of a message

Some _messaging infrastructures_ offer transactional semantics spanning the `Send` and `Consume` calls so that the received incoming message is consumed atomically with sending outgoing messages -- either both succeed or none does.

## Outbox with deduplication

The outbox pattern stores the outgoing messages in a database alongside business-specific data (atomically with business state transition) and later attempts to push them out to their destinations. The stored messages are tagged with the ID of the incoming message that triggered the processing in order to allow de-duplication. The pushing out of the outgoing messages is driven by attempts at re-processing the incoming message. The outbox pattern with built-in deduplication can be illustrated by following pseudo-code:

- Invoke `Receive` -> incoming message (payload + ID)
- In case no outbox record exists for received message ID:
  - Begin database transaction
  - Invoke business logic for processing message -> collection of outgoing messages
  - Store outbox record as a tuple `(ID, outgoing messages)`
  - Commit database transaction
- Otherwise load outgoing messages stored in the outbox record
- For each outgoing message, invoke `Send`
- Update outbox record setting outgoing messages to `null`
- Invoke `Consume`

The source of the duplication in this approach is the fact that there is no atomicity between the `Send` operations and the updating of the outbox record that follows it. A failure between any two `Send` calls or between the last `Send` call and the update results in a retry that repeats at least one of the `Send`s that already succeeded.

For this reason the de-duplication based on the message ID is necessary element of the pattern. It is essential that the message IDs used for the deduplication are stored in the database and not re-generated every time `Send` is invoked.

## Deduplication data

The pattern described above does not require transaction semantics between `Send` and `Consume` which makes it easy to adopt to almost any _messaging infrastructure_. The downside is that is requires that the outbox records containing the ID of processed messages are kept for de-duplication purpose for extended periods of time. Most implementations available as packaged libraries used several days as a default (e.g. 7) but do not provide any good explanation for the specific value.

TODO: Add more information about why storing the data is bad

## Transacionality

Some _messaging infrastructures_ offer transaction semantics between the `Send` and `Consume` calls. This article proposes a revised approach to outbox that takes advantage of this capability to remove the need for keeping any deduplication data. We are going to describe the new approach via a series of modifications to the outbox pattern.

The first step is to combine the `Send` and `Consume` calls in the outbox flow in an atomic transaction. This ensures that no duplicates are introduced by the process of pushing out messages to the _infrastructure_.

This, however, creates the problem as the `Update outbox record` step can succeeed while the following `Consume` fail. The `Consume` failure causes the `Sends` to be rolled back as well. As a result, when the incoming message is delivered again, the outbox record is empty -- the outgoing messages are lost.

To prevent this, we need to remove the `Update outbox record` step from this sequential flow and trigger it by a _control message_ send by the processing code to _itself_. The _control message_ is injected into the outbox collection so the resulting flow is following.

- Invoke `Receive` -> incoming message (payload + ID)
- In case no outbox record exists for received message ID:
  - Begin database transaction
  - Invoke business logic for processing message -> collection of outgoing messages
  - Add _control message_ with ID of the incoming message to the collection of outgoing messages
  - Store outbox record as a tuple `(ID, outgoing messages)`
  - Commit database transaction
- Otherwise load outgoing messages stored in the outbox record
- Beging messaging transaction
- For each outgoing message, invoke `Send`
- Invoke `Consume`
- Commit messaging transaction

When _control message_ is received:
- Remove outbox record

Note that we could change the `Update outbox record` step to `Remove outbox record` because there is no place in the system that can generate duplicate messages. 

## Duplicate processing

There is, however, still a risk of duplicate message _processing_ even though messages themselves are not duplicated. The risk stems from the fact that _messaging infrastructure_ in order to guarantee eventual message processing has to give up waiting for receivers that take arbitrary long time to respond. This is done via _lease_ mechanism. Each receiver gets a limited window of time to process a message and when that window elapses, a new _lease_ is generated and message is handed to another instance of the receiver.

If the original receiver did not fail but rather was paused, we end up in a situation in which two threads are racing to process the same message. If the pause of the second thread was long enough to allow the first thread to complete its flow, including processing the follow-up control message, the second thread can reach the `Commit database transaction` when the outbox record no longer exist. This means that the transaction succeeds and the business state transition is applied for the second time, corrupting the data.

Note that even in this case no duplicate messages are introduced to the system as the `Send`-`Consume` transaction that follows the `Commit database transaction` step is going fail as the message has alredy been consumed.

## TBD ???

In order to prevent duplicate processing the receiving thread needs to confirm it is the owner of the message _lease_ while also ensuring that it is the first to commit the outbox database transaction. 

In ordet to do this, we need to introduce another field to the outbox record -- `Attempt ID` -- resulting in the following flow:

- Store outbox record containing only ID of the incoming message `(ID, null, null)`
- Begin database transaction
- Invoke business logic for processing message -> collection of outgoing messages
- Add _control message_ with ID of the incoming message to the collection of outgoing messages
- Update outbox record with `(ID, outgoing messages, Attempt ID)` if stored `Attempt ID` is `null`
- Invoke `Confirm-Lease` API of the messaging infrastructure
- Commit database transaction

In order to explain how it works we need to analyze three potential pause situations:
- The second thread was paused before storing the outbox record
- The second thread was paused before confirming the lease
- The second thread was paused after confirming the lease

All of these situations assume that the first thread has committed it `Update outbox record` step.

### Puase before storing

In this case the second thread can successfully execute the flow until the `Confirm-Lease` call. This call fails as the received message has already been consumed. This prevents duplicate processing by aborting the database transaction

### Pauase before confirming lease

This case results in the behavior similar to the one above

### Pause after confirming lease

In this case the `Update outbox record` step fails because the outbox record to be update does not exist or exists with a non-null `Attempt ID`.

## TLA+ model

TODO

## Discussion

It is possible to build an outbox-based algorithm that ensures exactly-once processing of messages delivered via durable asynchronous messaging infrastructure that does not need to accumulate de-duplication data in the database.

In the algorithm we proposed the deduplication data is stored only for the duration of each message processing attempt and is evicted immediately afterwards.

The apprach requires the _messaging infrastructure_ to provide transactional semantics between `Send` and `Consume` operations, as well as an API for confirming the message _lease_.

Compared to the baseline outbox implementation, the proposed algorithm adds two I/O-bound steps to each processing attempt. One is due to the fact that it replaces a single `INSERT` operation for the outbox record with a `INSERT` followed by an `UPDATE`. The second additional step is the `Confirm-Lease` call to the _messaging infrastructure_.

This additional cost is, however, rather small compared to the benefits of not accumulating large amount of de-duplication data.

In terms of real-world usage, Azure Service Bus is a good candidate for using the proposed algorithm:
 - It offers the tranactional `Send` and `Consume` mode that does not incur significant performance penalty compared to non-transactional operations
 - It exposes `Renew-Lock` API that has the semantics required by the `Confirm-Lease` operation: succeeds if a caller holds a valid lease and fails if the provided lease ID is invalid
