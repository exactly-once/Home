# Improving the Outbox

In [one of the previous posts](https://exactly-once.github.io/posts/outbox/) we introduced the Outbox pattern. The Outbox implements the consistent messaging idea by storing the ID of the incoming message and the collection of outgoing messages in the outbox records inside the application database. The correctness of the Outbox behavior depends on the ability to tap into the application state change transaction. The big advantage of this pattern is its relative simplicity, compared to alternative solutions. Worth noticing is also the fact that, at least in the .NET world, there is a high-quality implementation readily available in NServiceBus. In fact NServiceBus has the support for the Outbox pattern since version 5 (which dates back to September 2014) and there are thousands of endpoints running the Outbox algorithm in the wild without any problems. So why should we change anything? 

You may remember that we discussed two main issues in with the Outbox pattern. If not, we'll remind you. The first issue is connected with the tight coupling between the deduplication information (the ID of the incoming message) and the processing outcome information (the outgoing messages). Because of it, is is not possible to implement the Outbox pattern over a storage that does not support multi-entity transactions and robust querying. In practice, this limits the applicability of the Outbox pattern to the relational databases.

The second issue is the non-deterministic deduplication data eviction. The information about the processed messages is removed based on its age, following the assumption that duplicates are spaced closely on the time axis and that the likelihood of a duplicate arrival goes down super-linearly with the time elapsed from the first delivery. In other words, the most prevalent strategy is to keep the deduplication data for a week and hope that it is enough. Well, we think we can do better.

## Decoupling

In this post we will attempt to address the first problem. Let's look again at the Outbox pattern

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
    await Dispatch(context, toDispatch);

    entity.OutboxState[messageId].OutgoingMessages = null;

    await persister.Persist(entity);
}
{{< / highlight >}}

The root cause of the issue can be easily seen in line 34 where we remove the content of the outgoing messages but we leave the ID of the incoming message. Why? Because we need it for the deduplication check done in line 5. 

What can we do to remove the need for keeping all these message IDs around as part of the entity state? Notice the requirement for correct deduplication is that we need to keep the IDs of all processed messages for the entire deduplication period without any interruptions but it does not state where these IDs are stored. As long as they are **in at least one location**, we can move them around at will. So how about this:

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
await deduplicationStore.Add(messageId);
entity.OutboxState.Remove(messageId);
await persister.Persist(entity);
{{< / highlight >}}

This code satisfies this requirement as we first add the deduplication information to an external store and then persist the new state of the entity. As a careful reader, at this point you might ask about the consitency models of these two operations. What we really want to achieve is to make sure that the deduplication store write not only happens but also **is visible** to all readers before we clean up the outbox stated. We will come back to this subtle detail later, when we get to implementation technologies. Now we need to take this new store into account in the deduplication check. Previously we only checked the collection inside the entity

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

TransportOperation[] outgoingMessages;
if (!entity.OutboxState.ContainsKey(messageId))
{
    //Execute business logic
{{< / highlight >}}

Now we also need to take into account the external store

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var entity = await persister.LoadByCorrelationId(correlationId)
                   ?? new Entity { Id = correlationId };

if (await deduplicationStore.HasBeenProcessed(messageId))
{
    return;
}
TransportOperation[] outgoingMessages;
if (!entity.OutboxState.ContainsKey(messageId))
{
    //Execute business logic
{{< / highlight >}}

## Devil is in the detail

There are two subtle things worth noting here. First, we can use an early return in line 6 because we know that outgoing messages are always dispatched prior to creating an entry in the deduplication store. Second, we need to execute the check **after** the entity has been loaded. Why is it so important? Consider a situation when two identical messages arrive. The first copy is processed to the point just before creating the deduplication entry. Then the second copy is picked up and passes the deduplication check based on the external store. Then the first thread continues and removes the deduplication information from the entity. Then the second thread loads the entity and continues processing without any problems. Result? Customer's credit card debited twice.

With the code like the one above, where the deduplication check happens after the entity is loaded, the optimistic concurrency check will prevent the second thread from successfully committing the application state transition. The message will get back to the queue and when it will be picked up again, the deduplication entry that now exists will prevent duplicate processing.

Here's the full code with added and changed lines highlighted:

{{< highlight c "linenos=inline,hl_lines=4 5 6 7 39 40,linenostart=1" >}}
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

## Deduplication store

You might be now asking a question about what would be a good deduplication store. Well, that, of course, depends on your environment. For a solution deployed on-premises, almost any decent database would be fine. In Azure Cosmos DB and Blob Storage are both good candidates, but with an important caveat. If you decide to use the Cosmos DB, make sure to select [strong consistency](https://docs.microsoft.com/en-us/azure/cosmos-db/consistency-levels). Otherwise, the algorithm would not work as the deduplication checks might be executed against a stale version of the store. If you enjoyed our [previous post on model checking](https://exactly-once.github.io/posts/model-checking-exactly-once/), you might want to read about [TLA+ models of Cosmos DB consistency levels](https://github.com/Azure/azure-cosmos-tla).

Last but not least, if you are AWS an obvious choice might seem to be S3 but in fact it would lead to an incorrect behavior. The [S3 consistency model](https://docs.aws.amazon.com/AmazonS3/latest/dev/Introduction.html#ConsistencyModel) guarantees strong consistency (reads always return the latest state) only for keys which have not been previously read. In other words, if you `PUT` to a key, a subsequent `GET` is guaranteed to return the current value. But if you `GET` a key first, then `PUT`, and `GET` again, you can get a stale value -- the one returned by the first `GET`. Unfortunately this is exactly the flow required by our algorithm. Fortunately Dynamo DB is a good alternative.

## Working code or it didn't happen

While the algorithm explained in this post has indeed some considerable advantages over the classic Outbox algorithm, we don't intend to provide a production-ready implementation of it. We believe we can give you an even better solution so treat this one as a stepping stone, a brief stop in our pursuit of high-quality exactly-once processing implementations for contemporary data stores and messaging technologies.

However, if you wish to take a look at the working code, it can be found [here](https://github.com/exactly-once/outbox-based-consistent-messaging/blob/master/src/BasicInbox/SagaManager.cs). It is part of a solution that contains a number of proof-of-concept implementations of various deduplication approaches. Next time we will show you how the separate deduplication store approach can be optimized for one of the most popular cloud data stores -- Cosmos DB.
