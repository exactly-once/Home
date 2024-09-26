# De-duplication at the boundary

## Outbox

The outbox can ensure that the outgoing messages are published atomically with the application state change that is happening while handling the HTTP request. By itself, however, it can't offer any way of de-duplicating the incoming requests.

## Client-assigned IDs

In this approach the client is responsible for assigning unique IDs to actions. If a given actions is retried, the new HTP request is expected to carry the same ID. This ID can be used for de-duplication. 

## Client-side request throttling

The user interface can limit the number and the type of outstanding HTTP requests to ensure that the state the user sees in the UI does not diverge too much from the persistent state of the application. For example, if there is "Add item" button, the UI may allow only one outstanding `AddItem` request by ignoring subsequent clicks or disabling the button until a response is received for the previous action. 

The downside of this approach is the fact that the UI may seem unresponsive.

## Draft-publish pattern

In this pattern the user actions are categorized into two sets. First, the user modifies a private set of data that is not visible to the other users. These modifications do not involve publishing any messages. Because the data set is private, there is no need for client-side request throttling. In the worst case an action is executed more than once but the problem will be noticed next time the UI is refreshed. When the data set is ready the user publishes it in a single action. This action involves no modifications of the data and resulting in publishing a message (or a set of messages). It also sets a flag to indicated that this data set has been published. 

## Token-based de-duplication

Token-based de-duplication is not possible at the boundary because components outside cannot be expected to participate in the protocol. 

## Driving the message publication

In the classic outbox solution the message publication is driven by the message processing retry mechanism. If publishing of outgoing messages fails, the incoming message is returned back to its queue and when it is picked up again, the publishing of outgoing messages is invoked.

At the boundary where incoming invocations come in the at-least-once way this approach is not possible. Alternative are:
 - client-driven retries - where the client is responsible for re-issuing HTTP requests if no response is received or if the response code indicates the need for retry
 - polling - where there is a background process that picks up dropped outbox transactions and drives them to completion
 - change-feed - in this approach the dropped outbox transactions are picked up by a function that uses a change feed trigger
