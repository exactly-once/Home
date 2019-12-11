# Distributed business processes

In the [previous post](https://exactly-once.github.io/posts/messaging-infrastructure/) we explained what a messaging infrastructure is. We showed that it is necessarily a distributed thing with parts running in different processes. We've seen the trade-offs involved in building the messaging infrastructure and what conditions must be met to guarantee consistent message processing on top of such infrastructure. This time we will explain why it is reasonable to expect that most line-of-business systems require a messaging infrastructure.

## Architecture is not an exact science

There are two types of architects our there. There are ones that will tell you exactly what patterns and technologies you should use even before you have a chance to explain them what problem your system is solving. There are also ones that will tell you either "it depends" or "you milage may vary" even if you given them exact specification of the application. That says a lot. Software architecture is not an exact science. There is very little hard rules justified by solid research. Most of it boils doing to which conference you have attended recently. But do not despair. It turns out that if you look under the buzzword-ridden surface, there are actually concepts there that can be studied with more rigour.

## State change

The most fundamental thing in line-of-business software is a state change. State changes are the very reason we build such software. A system reacts on real-world events by changing its state. When you click "submit" an order entity is created. On the other end the state change of the system triggers an event in the real world. When the order is state is set to "payment succeeded" the parcel is dispatched to the courier.

## Chains of state changes

A system as described above consists of a single data store and a single processing component. That is not how modern software systems are built. Regardless of your approach to architecture, the system is, sooner or later, going to consist of multiple components. One common thing that we can identify in such a system is chains of state changes, one triggering another.

TODO: Simple diagram

When you click "submit", the order and shipment entities are created. When the payment succeeds the order entity is modified. But that's not enough to get you need phone delivered to your door. When the order state is set to "payment succeeded", the shipment entity has to be modified too in order to unlock the delivery. One state change triggers another state change, possibly in another part of the system.

## Distributed business processes

We call these chains of state changes triggering one another distributed business processes. You can find them in most line-of-business systems. They are interesting because they are not specific to the approach to architecture you may have. 

Looking at the distributed business processes in more formal way, we can describe them using following statements:
- if the initial change has been persisted, the follow-up change will eventually be persisted too
- for each instance of initial state change, the follow-up state change has to occur exactly once
- the process that executed the follow-up state change has to see the initial state change as done

A necessary element of each distributed business process is communication. The fact that the initial state change has occurred needs to be communicated to the code that executes the follow-up change. Let's see what is required for such communication.

### Reliability

We want the communication to be reliable to make sure that the message that should trigger the follow-up change is not lost.

### De-duplication

We want the messages that trigger the follow-up change to be de-duplicated in such a way that if the follow-up change is already persisted, receiving another copy of the trigger message has no effect.

### Causal order

We want the message that triggers the follow-up change to not be delivered before the initial state change is durably persisted.

## Consistent messaging

We mentioned [consistent messaging](https://exactly-once.github.io/posts/consistent-messaging/) before

>we want an endpoint to produce observable side-effects equivalent to some execution in which each logical message gets processed exactly-once. Equivalent meaning that it’s indistinguishable from the perspective of any other endpoint.

Now we can see that this definition is not enough to guarantee correct distributed business process execution. In addition to the above, we also need causal order and reliable delivery. That translates an additional clause:

>if the side effects include sending out messages, the messages should not be dispatched before other side effects are persisted. Dispatched messages should be stored durably.

## Idempotence is not enough

It is a common misconception that idempotence, as a property of a persistence code, is all that is required to build distributed systems. Well, not when distributed business processes are considered. Let's assume that the state change application is idempotent. That means it can be applied multiple times and the side effects (in this case the state of the data) is exactly the same as if it was applied only once. We will now use that idempotent state change operation in our message handler. The handler is receiving messages and sending out messages to trigger the follow-up state change.

We receive a message and invoke the idempotent state change operation. Now we should send out a messages that informs about the state change. But what state change? We don't know if any state change occurred as part of this execution. All we know is the current state is exactly as if the change occurred exactly once. The only message we can send would carry the current state. Such a message is useless as far as distributed business processes are concerned because it cannot trigger any follow-up changes. The distributed business process cannot continue.

## The input-core-output model

Based on the above one can create a model of a distributed system that consists of three layers. The first layer is the input layer. It consists of components that handle synchronous communication with the external world. The famous shopping basket component fits in this layer.

Next up is the core layer. Between the input and the core layers there is the [sync-async boundary](https://exactly-once.github.io/posts/sync-async-boundary/). Components sitting at the boundary generate async messages compatible with consistent messaging rules based on the data captured in the input layer. The core layer consists of message handlers capable of communicating according to the rules of consistent messaging. Distributed business processes such the order handling process or shipping process live here.

The third layer is the output layer. It consists of message handlers that are *merely* idempotent. Although their logic handles duplicate messages correctly, they are not able to emit messages that could trigger follow-up state transitions. You might find here a message handler that processes an `InvoiceRequested` event and generates a PDF document to be stored in the Blob Storage. If the triggering message gets duplicated, the handler will generate another copy of the PDF document but will detect duplication when attempting to store a new blob. You might also find here a handler that processes `AuthorizeCreditCard` commands and calls external payment API. Because such a handler takes the `PaymentId` field of the incoming message and sends as `TransactionReference` to the payment provider, that provider can correctly de-duplicate calls.

In this model messages always flow left-to-right between the layers. Inter-layer messages are only allowed in the core layer. Can you fit your distributed system into this model? We would like to hear your opinions. Challenge us on Twitter!
