---
layout: post
title: Token-based deduplication 
date: 2020-08-27
author: Tomek Masternak, Szymon Pobiega
draft: false
---

# Token-based deduplication

One problem left unsolved by our previous attempts at designing a deduplication solution is the non-deterministic nature of data eviction. We know we can't keep the deduplication data forever but when can we safely delete it? Unfortunately there is no good answer. The longer we keep the data, the less likely we are to miss a duplicate message. Fortunately there is a way to solve the problem.

## When it's gone, it's gone

So far our algorithms depended on the existence of information to be able to discard a duplicate message. In the absence of such information a message was considered legal. This approach is the root cause of the data eviction problem. So let's try to invert it. In the new algorithm a message can be processed only if deduplication information *is present*. If it is absent, a message is considered a duplicate. We are going to call that piece of information *a token*. The token for a given message is removed after the message is processed, preventing other copies of that same message to be processed.

## First draft

Let's take a look again at the improved outbox algorithm from the previous post. The highlighted lines are the first places that need to be modified.

{{< highlight c "linenos=inline,hl_lines=4 5 6 7 39,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

if (await deduplicationStore.HasBeenProcessed(messageId))
{
    return;
}

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
    await Dispatch(context, toDispatch);

    await deduplicationStore.Add(messageId);
    entity.OutboxState.Remove(messageId);

    await persister.Persist(entity);
}
{{< / highlight >}}

The duplicate check in lines 4-7 needs to be inverted so that if the token is not present in a token store, we return without processing the (duplicate) message. Next, we need to ensure we delete the token. That should be done in line 39. Last, but not least, we need to created the tokens for the messages that are sent out. That needs to be done *before* the messages are dispatched. We end up with the following code.

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

if (!await tokenStore.ContainsToken(messageId))
{
    return;
}

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
    var tokens = outgoingMessages.GenerateTokens();
    await tokenStore.CreateTokens(tokens);

    var toDispatch = outgoingMessages.Deserialize();
    await Dispatch(context, toDispatch);

    await tokenStore.RemoveToken(messageId);
    entity.OutboxState.Remove(messageId);

    await persister.Persist(entity);
}
{{< / highlight >}}

## Make it work

Does it work already? As a first check, imagine two copies of the same message arriving at the same time to a multi-threaded consumer. Both threads start executing the algorithm at roughly the same time so they do the check in line 4 before any of them reaches line 42. Fortunately for us, our old trusted friend optimistic concurrency won't allow one of the threads to reach that far. The optimistic concurrency check at line 26 is going to stop one of the threads and force it back. When it starts processing the duplicate message again the outbox state already indicates the message has been processed. As our friend Andreas says, disaster averted.

Now let's imagine a different scenario. An upstream endpoint that sends messages to our endpoint struggles and fails processing its message just before line 42. At this point the token has already been created and the message has been sent. Our endpoint starts processing and is quickly done with it. The token has been removed. 

In the meantime the upstream endpoint recovers from the failure and start re-processing the message that failed. Its own token has not been removed yet but the outbox state indicates that the incoming message has been processed so the algorithm skips to line 36. It generates a brand new token and sends a message. This is the same logical message as we already processed but has a brand new token associated with it so our endpoint won't treat it as a duplicate. We are doomed.

The problem here is that for the algorithm to work we need to ensure that tokens are never re-created once the messages are dispatched. This can be solved by adding an additional check point in the algorithm and using token IDs that are generated unique for each attempt.

{{< highlight c "linenos=inline,hl_lines=36 37 38 39 40 41,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

if (!await tokenStore.ContainsToken(tokenId))
{
    return;
}

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
    if (!outgoingMessages.HaveTokens())
    {
        var tokens = outgoingMessages.GenerateTokens();
        await tokenStore.CreateTokens(tokens);
        await persister.Persist(entity);
    }

    var toDispatch = outgoingMessages.Deserialize();
    await Dispatch(context, toDispatch);

    await tokenStore.RemoveToken(tokenId);
    entity.OutboxState.Remove(messageId);

    await persister.Persist(entity);
}
{{< / highlight >}}

The lines 36-41 show that new checkpoint. Each execution of these lines generates a brand new set of tokens under new IDs. The first successful execution (that is one that completes line 40) persists the IDs of generated tokens in the outbox state and the messages that are dispatched carry these token IDs.

## Discussion

We managed to successfully modify the improved outbox algorithm to avoid having to rely on non-deterministic deduplication data cleanup. The amount of space the new algorithm uses is stable and proportional to the number of in-flight messages. Good job. Now let's think about the other consequences.

First, we added an additional checkpoint. That means yet another roundtrip to the business data storage. We need to take that into account when planning the capacity of the infrastructure.

Next, the token store. It is very similar to the deduplication store we introduced previously but there are some notable differences. In case of the deduplication store we didn't have any code on the hot path that would remove records from it. We silently assumed there is some magic hand that removes the old deduplication records. Some storages indeed support such magic hand e.g. Cosmos DB implements the time-to-live markers on the documents. The token store works differently. Tokens are explicitly removed after a message has been processed. This difference means we have yet another roundtrip to do.

Last but not least, garbage. Because each token generation attempt creates tokens under brand new set of IDs and only the last (successful) batch of tokens is actually used, we may end up with tokens that are not going to be deleted. In fact there is no good way to tell if a given token belongs to a message that has been stuck somewhere and is going to be processed later or is just a garbage. Fortunately we can use the *register-cleanup* approach described in [one of the previous posts](https://exactly-once.github.io/posts/intuition/) to prevent garbage. Of course this has a price and that price, as you now might expect, is one roundtrip (at this point you may be thinking that roundtrips are universal currency and you can buy anything with it).

To summarize, the token-based deduplication approach offers a safer way to ensure exactly-once message processing by eliminating the non-deterministic data eviction. The trade-off is three additional roundtrips to data storages for each message processed. Fortunately the modern cloud storages offer a very convenient pricing model where you can actually check how much you pay for the nice cozy feeling of being safe from duplicate messages. And we think the price is actually not that high. In one of the next post we are going to revisit the token-based approach and show how it can be used in other, than messaging, communication approaches.
