# Outbox

In the previous post we have shown how consistent messaging can be implemented by storing point-in-time state snapshots and using these snapshots for publishing outgoing messages. We discussed some pros and cons of this approach. This time we will focus on the alternative approach which is based on storing the outgoing messages before they are dispatched.

Consistent messaging requires the ability to ensure exactly same side effects (in form of the outgoing messages) each time a copy of a given incoming message is processed. One way of fulfilling that requirement is to capture and persist these side effects as part of the state of the object. Once persisted, these side effects can be re-played each time a copy of the incoming message is received. The main advantage of this approach is simplicity. The user no longer needs to worry about making the processing logic deterministic (including accessing system clock or random number generator).

Let's take a look at the code to understand better all the moving parts. First, we need to load the state of our business component. 

```
var stateContainer = await persister.LoadByCorrelationId(correlationId).ConfigureAwait(false) ?? new StateContainer { Id = correlationId };

TransportOperation[] outgoingMessages;
if (!stateContainer.OutboxState.ContainsKey(messageId))
{
```

As you can see, the state container is extended with a data structure that holds the message processing state -- `OutboxState`. That structure is a map that associates ID of an incoming message with a collection of outgoing messages that were produced during processing. When a message handler receives a message, it loads the state and inspects the _Outbox_ to check if it contains an entry for the ID of the incoming message. If there is no corresponding entry, it means that a given message has not been processed yet.

```
var state = (T)stateContainer.State ?? new T();
var (newState, pendingTransportOperations) = await handlerCallback(state, context);
```

In that case we invoke the business logic that returns a tuple containing a new value of the state and a collection of `pendingTransportOperations` -- messages that were generated and are to be dispatched. Now we need to take both these pieces, stick them into the container and make sure they are stored durably in a *single atomic operation*.

```
outgoingMessages = pendingTransportOperations.Operations.Serialize();

stateContainer.State = newState;
stateContainer.OutboxState[messageId] = new OutboxState
{
    OutgoingMessages = outgoingMessages
};

await persister.Persist(stateContainer);
```

Let's go back and look at the other branch of the `if` statement. What if the condition

```
if (!stateContainer.OutboxState.ContainsKey(messageId))
{
```

is false. What if the _Outbox_ state already contains an entry for a given ID? That means we have already processed a another copy of the incoming message. There are two possible reasons for this. The message may simply be a duplicate. Another possibility is that there exists a single copy of that message but the first time we attempted to process it, we failed to dispatch the outgoing messages and the incoming message has been returned to the queue. 

```
outgoingMessages = stateContainer.OutboxState[messageId].OutgoingMessages;
```

If a message is indeed a duplicate, the collection of outgoing messages is `null` and we don't need to do anything. You may be wondering now what happens if two copies of a message come in at exactly the same time. It may be that one thread manages to persist the _Outbox_ state before the other begins the processing. In that case the second thread will see the outgoing messages as not `null` even though the message is a duplicate. As a result, the outgoing message will be dispatched two times, however this is not a problem as the receivers of these messages will be able to de-duplicate them.

```
if (outgoingMessages != null)
{
    var toDispatch = outgoingMessages.Deserialize();
    await Dispatch<T>(context, toDispatch);

    stateContainer.OutboxState[messageId].OutgoingMessages = null;

    await persister.Persist(stateContainer);
}
```

There is another reason why we need to *nullify* the outgoing messages. The take up space. We don't want our state to grow with each message sent. To prevent it, we remove the outgoing messages that we know we successfully sent, leaving `null` value as a sign that a given message has been successfully processed end-to-end.

As you can see, the _Outbox_ pattern is fairly straightforward. It can be implemented on top of any data store and does not require event sourced approach to persistence. You are probably wondering now what are the downsides. There is a couple. We will deal with them one by one.

The first issue is related to how the processed message information is stored. In case of the _Outbox_, it is part of the same document as the business state. This means that the more messages we process, the bigger the document becomes. The bigger it becomes, the more time it takes to process a single message. It is worth mentioning that some popular data stores, such as Azure Tables or AWS Dynamo, have strict limits on the data size.

The second issue is actually something that affects both solutions we've discussed so far. The problem is related to how long the de-duplication data is retained. Both solutions lack a deterministic way of evicting information about processed messages. The only option is to use the wall clock to delete information older than certain threshold. This strategy is based on the assumption that duplicates are much more likely to be placed closely on the time axis. In other words, it is much more likely to receive a duplicate 5 milliseconds after the original message than after 5 days. While this assumption seems reasonable, it might not hold true in cases of catastrophic failures where part of the messaging infrastructure is down for considerable amount of time and, when it goes up again, re-plays all the messages already processed.

In the subsequent posts we will discuss solutions to deal with both of these problems. Stay tuned!

