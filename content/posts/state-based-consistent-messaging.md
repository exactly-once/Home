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

First, we load a piece of state based on `BusinessId` and `Id` of the message. `LoadState` returns either the newest version of the sate or if the message is a duplicate, **a version proceeding the one which was the result of processing that message**. In other words, `LoadState` makes sure that the properly recreate historical state for duplicates.

These two scenarios (new vs. duplicate message) are represented in code by `DuplicatedMessages` flag. Based on its value the sate update step is either performed or skipped.

It's worth noting that message publication comes last and it's for a reason. Optimistic concurrency control based on the `version`  argument makes sure that in case of a race condition processing will fail before any [ghost message]() get published. 

### Implementation

The source code shown here only in parts can be found in [exactly-once](https://github.com/exactly-once/state-based-consistent-messaging) GitHub repository. 

#### State management

With the general idea of the solution let's look at the implementation details. It uses [EventSourcing](link) for storing the state which is by definition fulfills the requirement on state storage. More concretely, we will use [StreamStone](link) library which provides event store API on top of Azure Table Storage.

One of the questions that we still need to answer is how does the state storage manages the mapping between the id of the message and a given version of the state. This is done by leveraging event properties stored in addition to the event data itself. Here is a diagram that shows what is stored in the event stream as the messages get processed:

{{< figure src="/posts/state-based-storage-layout.png" title="State stream for a [A, D, B] message processing sequence">}}

Amongst others, the properties include a message identifier that enables detecting duplicates and restoring an appropriate version of the state.  During state recreation (aka. [rehydration](link)), when reading events from the stream the metadata field is checked to see if the current message identifier matches the one already captured. If so the rehydration process stops before reaching the end of the stream:  

{{< highlight c "linenos=inline,hl_lines=,linenostart=1" >}}
var stream = await ReadStream(partition, properties =>
{
      var mId = properties["MessageId"].GuidValue;
      var @event = DeserializeEvent(properties);

      if (mId == messageId)
      {
         isDuplicate = true;
      } 
      else if (@event != null)
      {
         state.Apply(@event);
      }

      return isDuplicate;
});
{{< / highlight >}}

The lambda passed as the last argument to `ReadStream` gets invoked for every event in a stream unless it returns false which indicates the end of the read. 

The duplicate detection requires that input message id is always captured, even if handling logic execution results in no state changes - [ShootingRange](https://github.com/exactly-once/state-based-consistent-messaging/blob/master/StateBased.ConsistentMessaging/StateBased.ConsistentMessaging/Domain/ShootingRange.cs#L9) handler logic for `FireAt` message is a good example of such case. In order to handle such case a dummy event is being stored with empty state delta.

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
}
{{< / highlight >}}

That said, line 7 where `Hit` message id is generated deserves more discussion. We are not using a standard libarary call to generate a Guid for a reason. As `Guid` generation logic is undeterministic form business logic perspective we can't use without breaking the second [requirement](#context). We need to make sure that on every re-processing of the same message the value of the guid will be identical to the origianl one. Some kind of seed data is needed to enable that - in our example the input message id plays that role and gets passed to the context just before handler execution:

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


Guid generation scenario touches on a more general case. The same kind of problem will exist for logic that uses random variables, time offsets or any other environmental variables that can change in between message invocations. In order to handle these cases as well we would need to caputre necessary invocation context in the event metadata (as show on the ) and expose utility methods on the `IHandlerContext` intance passed to the business logic.  

TODO: add information that only available operations are state modifications and message publication

### Pros and cons

We already mentioned the requirements needed for the state-based approach to message consistency. It's time to clarify what are advantages and disadvantages of this approach.

Advantages:

* Easy additon to event sorucing.
* Flexible de-duplication period based on the stream truncation rules.

Disadvantages

* Versioning might be harder.
* Stream size is proportional to number of messages processed.
* Esuring deterministic logic requires attention.

### Other approaches

AzureFunctions and asnc-await

TODO: 
 * talk about de-duplication period configuration, 
 * check links and add link to AzureFunctions

 
[^1]: 