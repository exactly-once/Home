---
layout: post
title: Outbox
date: 2020-03-06
author: Tomek Masternak, Szymon Pobiega
draft: false
---

In the previous post we have shown how consistent messaging can be implemented by storing point-in-time state snapshots and using these snapshots for publishing outgoing messages. We discussed some pros and cons of this approach. This time we will focus on the alternative approach which is based on storing the outgoing messages before they are dispatched.

Consistent messaging requires the ability to ensure exactly same side effects (in form of the outgoing messages) each time a copy of a given incoming message is processed. One way of fulfilling that requirement is to capture and persist these side effects as part of the state of the object. Once persisted, these side effects can be re-played each time a copy of the incoming message is received. The main advantage of this approach is simplicity. The user no longer needs to worry about making the processing logic deterministic (including accessing system clock or random number generator). Note that with this approach the business code may still be invoked multiple times but result of only one invocation is persisted.

The following code ensures the consistency of the message processing done by our business object.

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

TransportOperation[] outgoingMessages;
if (!entity.OutboxState.ContainsKey(messageId))
{
    var state = (T)entity.BusinessState ?? new T();

    var (newState, pendingTransportOperations) =
        await handlerCallback(state, context);

    outgoingMessages = pendingTransportOperations.Operations
                                                 .Serialize();

    entity.BusinessState = newState;
    entity.OutboxState[messageId] = new OutboxState
    {
        OutgoingMessages = outgoingMessages
    };

    await persister.Persist(entity);
}
else
{
    outgoingMessages = entity.OutboxState[messageId]
                             .OutgoingMessages;
}

if (outgoingMessages != null)
{
    var toDispatch = outgoingMessages.Deserialize();
    await Dispatch<T>(context, toDispatch);

    entity.OutboxState[messageId].OutgoingMessages = null;

    await persister.Persist(entity);
}
{{< / highlight >}}

That's a lot of code so to understand that better, let's examine it piece-by-piece. First, we need to load the state of our business component. 

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
             ?? new Entity { Id = correlationId };

TransportOperation[] outgoingMessages;
if (!entity.OutboxState.ContainsKey(messageId))
{
{{< / highlight >}}

The actual stored record contains two parts. There is the business state but there is also message processing state -- `OutboxState`. That structure is a map that associates ID of an incoming message with a collection of outgoing messages that were produced during processing. When a message handler receives a message, it loads the state and inspects the _Outbox_ to check if it contains an entry for the ID of the incoming message. If there is no corresponding entry, it means that a given message has not been processed yet.

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var state = (T)entity.State ?? new T();
var (newState, pendingTransportOperations) = 
                        await handlerCallback(state, context);
{{< / highlight >}}

In that case we invoke the business logic (`handlerCallback`) that returns a tuple containing a new value of the business state and a collection of `pendingTransportOperations` -- messages that were generated and are to be dispatched. Now we need to take both these pieces, stick them into the container and make sure they are stored durably in a *single atomic operation*.

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
outgoingMessages = pendingTransportOperations.Operations
                                             .Serialize();

entity.BusinessState = newState;
entity.OutboxState[messageId] = new OutboxState
{
    OutgoingMessages = outgoingMessages
};

await persister.Persist(stateContainer);
{{< / highlight >}}

Let's go back and look at the other branch of the `if` statement. What if the condition

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
if (!entity.OutboxState.ContainsKey(messageId))
{
{{< / highlight >}}

is false. What if the _Outbox_ state already contains an entry for a given ID? That means we have already processed another copy of the incoming message. There are two possible reasons for this. The message may simply be a duplicate. Another possibility is that there had been only a single copy of the message but the first time we attempted to process it, we failed to dispatch the outgoing messages and the incoming message has been returned to the queue. 

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
outgoingMessages = entity.OutboxState[messageId].OutgoingMessages;
{{< / highlight >}}

What's next? We can not push the outgoing messages to the transport and we are done. If another copy of the message comes in, the business logic will not be invoked and the persisted outgoing messages will be dispatched again. That behavior is correct but is not optimal for two reasons. First, it means that each time an incoming message is duplicated, the outgoing messages will get duplicated too. These outgoing messages get to another endpoint and cause duplicates there, too. We are not using the bandwith responsibly. Second problem is the fact that these outgoing messages take up preceious space in our entity, making it slower and slower to load and store it.

We can solve both problems by adding the optimization visible in the following snippet

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
if (outgoingMessages != null)
{
    var toDispatch = outgoingMessages.Deserialize();
    await Dispatch<T>(context, toDispatch);

    stateContainer.OutboxState[messageId].OutgoingMessages = null;

    await persister.Persist(stateContainer);
}
{{< / highlight >}}

The idea is to mark the fact that we managed to dispatch the outgoing messages. The easiest way is to set the outgoing messages collection to `null`. 

## Summary

As you can see, the _Outbox_ pattern is fairly straightforward. It can be implemented on top of any data store and does not require event sourced approach to persistence. You are probably wondering now what are the downsides. There is a couple. We will deal with them one by one.

The first issue is related to how the processed message information is stored. In case of the _Outbox_, it is part of the same document as the business state. This means that the more messages we process, the bigger the document becomes. The bigger it becomes, the more time it takes to process a single message. It is worth mentioning that some popular data stores, such as Azure Tables or AWS Dynamo, have strict limits on the data size.

The second issue is actually something that affects both solutions we've discussed so far. The problem is related to how long the de-duplication data is retained. Both solutions lack a deterministic way of evicting information about processed messages. The only option is to use the wall clock to delete information older than certain threshold. This strategy is based on the assumption that duplicates are much more likely to be placed closely on the time axis. In other words, it is much more likely to receive a duplicate 5 milliseconds after the original message than after 5 days. While this assumption seems reasonable, it might not hold true in cases of catastrophic failures where part of the messaging infrastructure is down for considerable amount of time and, when it goes up again, re-plays all the messages already processed.

In the subsequent posts we will discuss solutions to deal with both of these problems. Stay tuned!

