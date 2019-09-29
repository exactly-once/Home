# De-duplication: events vs commands

So far we looked at messages purely as way to transmit information between distributed processes. We intentionally ignored the matter of what is being transmitted. Now it is the time to change it.

In principle a message can carry any arbitrary sting of bytes. From the infrastructure point of view the payload of the message it not interesting. Really?

One of the common ways of categorizing message payloads is commands vs events. Commands are messages that carry a request for a state change. Event are messages that carry information about the state change that happened. If you happen to be part of the Domain-Driven Design community you might have a slightly different point of view. Events are recorded facts that can be communicated, among many other ways, by publishing a messages. Regardless of which definition you use, there is one fundamental difference between event messages and command messages.

## Business identity

Event messages have unique identity that comes from the face that they describe a state change that already happened. An example is `Order YZY submitted` event. The pair `(XYZ, Submitted)` uniquely identifies this particular event. If a subscriber service receives a second copy of `XYZ, Submitted)` event, it can be sure it is a duplicate as each event can be submitted only once. 

Command messages on the other hand do not carry any natural business ID. The request they carry can be rejected in which case there is no state change that can be associated any unique identity.

## State machine-based de-duplication

The fact that events have unique business identity opens a possibility for a form de-duplication based that identity. Assuming an entity can exist in a number of states and that a graph describing possible state transitions is acyclical, an entity needs to only remember its current state to be able to de-duplicate events associated with it. Let us give you an example again. On order is known to be in following states: `Placed`, `Submitted` and `Shipped`. The valid transitions are `Placed` to `Submitted` and `Submitted` to `Shipped`. When a services receives an event `(XYZ, Placed)` while its own representation of the order is in the `Submitted` state, it knows it can discard that event as a duplicate.

## Cycles

What if the business process does contain cycles? Can it be expected to adjust to this seemingly arbitrary requirement of acyclical transition graph? An example is an order submission process in which a `Submitted` order can rejected -- moved back to `Placed` state. Such a process contains a cycle between `Placed` and `Submitted` states that prevents us from using the state machine-based de-duplication.

## Missing business concept

A cycle such as the one described above is a sign that there is a business concept that is missing from the model. In this case it is *submission attempt*. An order may have multiple associated submission attempts, of which only one can be successful. In this extended model the state transitions of an order are again acyclical. There is also another entity, an attempt, that can be in one of the three states `Submitted`, `Accepted` or `Rejected`.

## Coupling

Any process with a cycle can be broken down into a hierarchy of acyclical processes like we have shown above. Doing so uncovers a missing business concept, in our case the *submission attempt*. In order to implement the new model the subscriber service needs to be modified to include the new concept which increases the coupling between the two services. That's bad, right?

We don't think so. In fact, adding the *submission attempt* concept just makes the coupling explicit. Previously the high coupling between the two services manifested itself in the cycle of the business process and was hidden away. Now that we broken the cycle and given the name to the concept, the coupling is visible at a glance. It should spawn a conversation about the service boundaries. Maybe we can shift them slightly so that the other service only needs to be informed when a submission attempt succeeds? This way it does not have to have the concept of attempt and the whole complexity of retrying submissions becomes an implementation detail of the publishing service.

## Summary

So far we've seen that events can be de-duplicated based on the state of the entities they related to. We've also seen that the same approach cannot be used for commands. If we can't use this new algorithm for all our messages, why is that even interesting?

It is interesting because it is commonly accepted that in a distributed system commands should not be used between the top-level components (let's call them services) but only within them. All communication between the top-level components should be done via events (link to ADSD). As a consequence, a different approach to ensuring exactly-once message processing can be used within the boundaries of a service to the one outside its boundaries. Components of a service are tightly coupled. We can use a atomic store-and-publish technology for implementing communication between them. Examples of such technologies include distributed transaction with MSMQ and SQL Server and using SQL Server as a message queueing infrastructure.
