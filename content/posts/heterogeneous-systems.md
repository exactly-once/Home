# Heterogeneous systems

Previously in the series (LINK to event-vs-command) we mentioned that a system may utilize two different approaches to *exactly-once message processing* based on the type of message. Event messages can be de-duplicated by a state machine-based approach that uses the business identity of the events. In the same system the commands may use a different approach, e.g. *atomic store-send-and-consume*.

We've also mentioned that a common practice is to restrict communication via commands to one service and use events for cross-service communication exclusively. Such approach means that each message type is associated with one approach to *exactly-once processing*, no matter how/when/where it is sent and received.

## Heterogeneous systems

Some systems are, however, designed in a different way. Instead of associating the type of a message with the *exactly-once processing* strategy, they associate top-level components (services) with these strategies. In such systems messages can be sent by *atomic store-send-and-consume* component and received by *atomic store-and-send* one or vice versa. Even if both parts use *atomic store-and-send*, they might use different methods for de-duplicating messages.

Why would one build such a complex system? Of course no architect gets up one day and says "Let us add some complexity to our system", right? Heterogeneous systems are a result of changing environment. Maybe one part of the system has been built on-premise where *atomic store-send-and-consume* infrastructure was already set up and available and the other part added later after the company's CIO decided that all new code must be deployed to the public cloud? Or maybe the organization became so successful that is acquired a competing company and needed to integrate its IT systems?

## End-to-end exactly-once processing a heterogeneous system

We hope that by this time you developed your messaging intuition enough to know that ensuring end-to-end *exactly-once* behavior should not be the responsibility of business components. One of the biggest advantages of asynchronous one-way messaging is the fact that intermediaries can be inserted between communicating components without these components being aware of it. 

A de-duplicating bridge 
