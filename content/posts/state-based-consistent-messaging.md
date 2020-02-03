---
layout: post
title: State-based consistent messaging
date: 
---

In the previous posts, we described consistent messaging and justified its usefulness in building robust distributed systems. Enough with the theory, it's high time to show some code! First comes the state-based approach.

## Context

State-based consistent messaging comes with two requirements:

* "Point-in-time" state availability - it's possible to restore any past version of the state.
* Deterministic message handling logic - for a set state and input message every handler execution gives the same result.

## Idea

Given the requirements, the general idea of how to achieve consistent message processing is quite simple. When dealing with a message duplicate we need to make sure the handler operates on the same state as when the message was first processed. With this and deterministic handler logic (handler being a pure function), we ensure that processing of a message duplicate results in identical state changes and output messages. 
 
Here is a pseudo-code implementation:

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
foreach(var msg in Messages)
{
    var (state, version) = LoadState(msg.BusinessId, msg.Id);

    var outputMessages = InvokeHandler(state, message);

    if(state.DuplicatedMessage == false)
    {
        StoreState(state, version)
    } 

    Publish(outputMessages);
}
{{< / highlight >}}

First, we load a piece of state based on `BusinessId` and `Id` of the message. `LoadState` returns either the newest version of the state or if the message is a duplicate, **a version just before the one when message was first processed**. In other words, `LoadState` makes sure to recreate the proper version of the state for duplicates. These two scenarios (new vs. duplicate message) are represented in code by `DuplicatedMessages` flag. Based on its value the state changes are either applied or skipped (for duplicates the state changes were already applied).

It's worth noting that message publication comes last and it's for a reason. Optimistic concurrency control based on the `version`  argument makes sure that in case of a race condition processing will fail before any [ghost message]() get published. 

### Implementation

Listings below show only the most intersting parts of the implementation. Full source code can be found in [exactly-once](https://github.com/exactly-once/state-based-consistent-messaging) GitHub repository.

#### State management

With the general idea of the solution in place let's look at the implementation details. For storing the state we use [StreamStone]() library that provides event store API on top of Azure Table Storage.

One of the questions that we still need to answer is how to store the mapping id to state version mapping. This is done by storing message id as event property for each entry in the stream. 

{{< figure src="/posts/state-based-storage-layout.png" title="State stream for a [A, D, B] message processing sequence">}}

When a new message gets processed a new version of the state is stored in an event which includes additional metatdata. These include message identifier that enables duplicates detection and restoring an appropriate version of the state. In `LoadState` when reading events from the stream the metadata field is checked to see if the current message identifier matches the one already captured. If so the process stops before reaching the end of the stream:  

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
// `ReadStream` iterates over a stream passing each event to
// the lambda. Iteration stops when reaching the end of the 
// stream or when lambda returns `false`.
var stream = await ReadStream(partition, properties =>
{
      var mId = properties["MessageId"].GuidValue;
      var nextState = DeserializeEvent<THandlerState>(properties);

      if (mId == messageId)
      {
         isDuplicate = true;
      } 
      else
      {
         state = nextState;
      }

      return isDuplicate;
});
{{< / highlight >}}

The duplicate detection requires that input message id is always captured, even if handling logic execution results in no state changes - [ShootingRange](https://github.com/exactly-once/state-based-consistent-messaging/blob/master/StateBased.ConsistentMessaging/StateBased.ConsistentMessaging/Domain/ShootingRange.cs#L9) handler logic for `FireAt` message is a good example of such case.

Versoning of the state doesn't surface to the busniess logic and is represented as POCO e.g.:

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
public class ShootingRangeData
{
   public int TargetPosition { get; set; }
   public int NumberOfAttempts { get; set; }
}
{{< / highlight >}}

#### Processing logic

At the business logic level the message handling doesn't require any infrastructural checks to ensure consistency:

{{< highlight c "linenos=inline,hl_lines=7,linenostart=1" >}}
public void Handle(IHandlerContext context, FireAt command)
{
   if (Data.TargetPosition == command.Position)
   {
         context.Publish(new Hit
         {
            Id = context.NewGuid(),
            GameId = command.GameId
         });
   }
   else
   {
         context.Publish(new Missed
         {
            Id = context.NewGuid(),
            GameId = command.GameId
         });
   }

   if (Data.NumberOfAttempts + 1 >= MaxAttemptsInARound)
   {
         Data.NumberOfAttempts = 0;
         Data.TargetPosition = context.Random.Next(0, 100);
   }
   else
   {
         Data.NumberOfAttempts++;
   }
}
{{< / highlight >}}

That said, line 7 where `Hit` message id is generated deserves more discussion. We are not using a standard libarary call to generate new `Guid` version for a reason. As `Guid` generation logic is undeterministic from business logic perspective we can't use it without breaking the second [requirement](#context). We need to make sure that re-processing of a message results identical output messages (including their identifiers). Some kind of seed data is needed to enable that - in our example the input message id plays that role and gets passed to the context just before handler execution:

{{< highlight c "linenos=inline,hl_lines=4,linenostart=1" >}}
static List<Message> InvokeHandler<THandler, THandlerState>(...)
{
   var handler = new THandler();
   var handlerContext = new HandlerContext(inputMessage.Id);

   ((dynamic) handler).Data = state;
   ((dynamic) handler).Handle(handlerContext, inputMessage);
   
   return handlerContext.Messages;
}
{{< / highlight >}}

Guid generation scenario touches on a more general case. The same kind of problem exists when using random variables, time offsets or any other environmental variables that might change in between handler invocations. In order to handle these cases we would need to caputre additional invocation context in the event metadata (as show on the diagram) and expose utility methods on the `IHandlerContext` instance passed to the business logic.  

In summary, for the handler to be deterministic it need to operate over business state and/or additional context data that gets captured during message processing.

#### Mind the gap 

The implementation of state-based consistent messaging has some gaps that require mentioning. First, in most real-world applications the state version storage reqruires clean-up. At some point the older versions are no longer needed e.g. after `n` number of days, and should be removed. This most likely requires some background clean-up process making sure this happens.

Secondly, the approach sotring the state has been chosen for it's clarity. It is likely that in production scenarios this might require optimizations from the storage size perspective e.g. storing state deltas instead of the whole snapshots and removing deltas for versions that already had their messages published.

Finally, the decission to hide state version from the business logic might not be necessary. In systems using [event sourcing]() for representing state the state-based approach might be integrated into persistence logic.

### Pros and cons

We already mentioned the requirements needed for the state-based approach to message consistency. It's time to clarify what are advantages and disadvantages of this approach.

Advantages:
* Easy additon to event sorucing.
* Flexible de-duplication period based on the stream truncation rules.

Disadvantages:
* Ensuring deterministic logic requires attention - making sure logic is deterministic might be error prone (though there is some [tooling]() that migth mitigate this)
* Managing business logic changes - changing business logic needs to be able to cope with historical versions of the state
* Stream size is proportional to number of messages processed - even if messages do not generate state changes


#### 

### Other approaches

AzureFunctions and asnc-await

TODO: 
 * talk about de-duplication period configuration, 
 * check links and add link to AzureFunctions

 
[^1]: 