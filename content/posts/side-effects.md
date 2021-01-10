### Side effects

In [the previous post](https://exactly-once.github.io/posts/token-based-deduplication/) we introduced the token-based deduplication approach. It inverts the traditional principle of deduplication. Instead of dropping a message if another copy of that same message is known to have been processed, the token-based approach drops a message if there is no token for processing it. In other words it uses negative (token does not exist), rather than positive (processing information exists), proof of duplication. 

The benefit of this approach is obvious. A pair of messaging endpoints does not generate unbounded deduplication information as they go. There are only as many tokens as required for the messages that are in-flight at any given point. 

In the previous post we demonstrated how token-based approach can be used to build message handlers that update local state and send out messages. In real life this is often not enough. Some of the most common needs include creating large documents (or blobs - binary large objects) and invoking HTTP APIs. 

In this post we will see how this approach can be extended to accommodate these other activities by introducing a general concept of _side effects_.

### Side effects

Side effects in the context of the token-based deduplication algorithm are any activities that influence things outside of the transactional data store used by the message handler. Let us recap here. The transactional data store is the database that holds both the business entity state and the algorithm state. Modification to that store is always done within a transaction that includes both business changes and the transition of the algorithm state.

Everything else is considered a _side effect_ e.g. sending a message, POSTing to a HTTP endpoint, creating a blob for the PDF invoice document etc. So given that there can be no atomic transaction between the targets of these side effects and the transactional store, how can we ensure correctness? We have seen in [the previous post](https://exactly-once.github.io/posts/token-based-deduplication/) that it can be done for outgoing message so let's try to apply the same technique in a more general way.

Let's think about requirements for correctly applying the side effects. Fist, **we want all side effects to be visible before the incoming message is consumed**. That condition includes that we of course don't want them to be omitted. Next, **we don't want any side effects to be visible if the incoming message have not been processed** e.g. because of processing logic throwing an exception. 

Third condition is less obvious. Because we need to always take into account possibility of attempting to process the same logical message concurrently by multiple threads, we need to ensure that the **side effects that are published all come from the same processing attempt**. For example if the message handler creates two blobs, we don't want to allow situation where each blob is created by different processing attempt as this could lead to inconsistent state if these handlers were not purely deterministic. 

Fourth and the last condition is about efficiency of storage usage. We don't want to crate any garbage so **by the time the message is processed successfully (consumed), all side effects that resulted from non-successful attempts should have been cleaned up**.

### Sketch of an algorithm

Looking at the above conditions we can try to sketch an algorithm. In [the previous approach](https://exactly-once.github.io/posts/token-based-deduplication/) we had our side effects (outgoing messages) serialized and stored in the transactional store alongside the business data. This is not a great approach if we want to support generalized side effects as they can be of significant size. A PFD document we want to store or send via e-mail can easily weigh few megabytes. There is no way we can include things like this as part of a document stored in CosmosDB.

That means we need to actually create side effects as we execute the handler and not store them serialized. But how about our second rule of not having them visible before the message is processed? Here's the trick. **Visible is not the same as created**. We can create a blob but before we tell about it, there is no side effect as far as other endpoints of the system are concerned.

So the first step is to create the side effect. That means uploading the bytes to create a blob document or creating a token if we are sending a message. This part is done when the code of the message handler executes

```c#
public async Task Handle(MyMessage message, IHandlerContext context)
{
    //Create the blob and record its URL in context
    await context.CreateBlob(blobUrl);

    //Create a blob containing the message body and record its URL in context
    await context.Send(new OtherMessage(blobUrl)); 
}
```

The second step is to actually publish the side effect. Blobs are published simply by including their URLs in the outgoing messages, as the code above shows. The messages themselves are published by pushing them to the destination queues (remember, tokens have already been created in the first step). To handle different types of side effects we need two types. One for representing the side effect and another for taking care of the publishing. Let's call these `SideEffectRecord` and `SideEffectHandler`.

```c#
public abstract class SideEffectHandler<T>
    where T : SideEffectRecord
{
    public abstract Task Publish(IEnumerable<T> sideEffects);
}
```

Take a look at the message handling code above. Does it satisfy all conditions? It fails on the third condition of not allowing results from different attempts to be mixed. Let's imagine two copies of a given message are picked up at the same time. Two threads, T1 and T2 start processing.
 - T1 creates the blob
 - T2 overrides the blob
 - T2 creates the message payload blob
 - T1 creates the message payload blob
 - T1 finishes processing, updates the transactional store and publishes a message
 - T2 fails on optimistic concurrency check

In this example T1 published the blob with contents created by T2. We risk creating inconsistent state if the handler used any non-deterministic API (query external service, use system clock, generate Guid etc.). Now let's look at the message sending. Both threads created the message payload blobs but only one managed to publish its messages. That means that the other blob becomes garbage. Let's try to fix it.

In order to satisfy the third (non-mixing side effects) condition we need to generate unique copies of side effects in each attempt. When we want to create a blob, we can't just create it under a hard-coded name like `pictures-of-cats.pdf`. We need to include a unique component in the URL (GUID). This way each attempt crates its own document and the attempt that wins publishes the URL to the blob it generated.

```c#
public async Task Handle(MyMessage message, IHandlerContext context)
{
    //Create the blob and record its URL in context
    var blobUrl = await context.CreateBlob(blobPrefix);

    //Create a blob containing the message body and record its URL in context
    await context.Send(new OtherMessage(blobUrl)); 
}
```

Now instead of using the same URL for the blob in all attempts, we generate a unique URL in each attempt. This change allows as to pass the third condition but also makes our algorithm even worse when it comes to garbage (condition four). This version not only leaves non-published messages but also blobs that have not been included in published messages. 

Back to the drawing board. But before we get there you might ask why exactly that garbage is bad? The problem with it is that there is no way to figure out what data is actually garbage other than looking for references (like garbage collection in managed language runtimes do). Here's one good reason to avoid garbage (other than esthetics). How do you explain why you keep you customer data in a PDF document after they deleted their account? I bet authorities doing the audit of the GDPR procedures won't buy the "it is just garbage" argument.

To recap, we can't use the same URLs for our side effects and we can't just generate unique values on the fly. Is there a way to get a value that is both unique (guaranteed to be different for each attempt) and deterministic so that we can clean it up later? Well, that's a problem very similar to *how do we make message IDs deterministic?* solved by the [Outbox](https://exactly-once.github.io/posts/outbox/). We need to generate a unique value and store it. Let's take a look at the `CreateBlob` method.

```c#
public static async Task CreateBlob(this IHandlerContext context, string blobPrefix)
{
    var unique = Guid.NewGuid();
    var url = blobPrefix + "-" + unique.ToString();
    var sideEffectRecord = new BlobSideEffectRecord {
        Attempt = context.Attempt,
        IncomingMessageId = context.IncomingMessageId,
        Url = url;
    };

    await context.TransactionalStore.Add(sideEffectRecord);
    await context.BlobClient.UploadBlob(url);
}
```

First, in line 3 we generate our unique value. Then in line 5-9 we construct the side effect record. As we mentioned previously, there is nothing to do when publishing blobs so this record is only needed for cleanup. Notice that in line 11 we store the side effect before we actually upload the blob in line 12. This ensures that we won't end up in a situation with an uploaded blob both without the corresponding side effect record. The cleanup loops through all side effects recorded for a given incoming message and cleans up the ones that have `Attempt` value different than the ID of the successful attempt.

Last but not least, conditions number one and two. How do we ensure the side effects are indeed published (and the ones that are to be cleaned up are removed) after we know it has been processed successfully but before it is consumed. This one is relatively simple. We need to inject the publishing of the side effects right after the transaction store transaction is committed. This ensures that we don't generate _ghost side effects_ -- side effects that carry the state that has not yet been made durable.

We also need to make sure the publishing happens before we clean up the transaction information from the store.

### Summary

Let's recap what the conditions for a correct side effects algorithm are:
 - we want all side effects to be visible before the incoming message is consumed
 - we don't want any side effects to be visible if the incoming message have not been processed
 - side effects that are published all come from the same processing attempt
 - by the time the message is processed successfully (consumed), all side effects that resulted from non-successful attempts are cleaned up

Our sketched up algorithm satisfies all four. The side effects are made visible when the transactional store transaction completes. All side effects come from the same (successful) attempt because we ensure their identity contains a unique value. We make sure to leave no garbage by recording the identity of side effects before thy are created and cleaning up data generated by failed attempts.

Two types of side effects we mentioned so far were outgoing messages and blobs. In the next power we will take a closer look at another type of side effect - a HTTP request/response. While we have you here, we would like to invite you to our workshops. On Feb 18-19 you can join us a [dotnetdays.ro](https://dotnetdays.ro/Workshops) and on Mar 12-12 on [NDC Workshops](https://ndcworkshops.com/slot/reliable-event-driven-microservices).
