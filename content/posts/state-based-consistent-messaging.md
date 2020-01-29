---
layout: post
title: State-based consistent messaging
date: 
---

In the previous posts we described cosistent messaging and justified it's usefulness in building robust distributed systems. Enough with the theory, it's high time to show some code! First comes the state-based approach.

## Context

The state-based approach to consistent messaging comes with few assumptions:

* "Point-in-time" state availability - we require that it's possible to restore any past state version,
* Message handling logic is deterministic aka. pure function - as long as the state version and input message are the same the executing handler logic will result in identical state modifications and output messages
* The state storage provides concurrency control - the store used for enpoint state enables handling "concurrent write" conflicts

## Idea

At a high level, what we want is to make sure that any message gets applied on the state at most once and secondly that message duplicates produce the same output messages on re-processing. Given the assumptions here is a draft of the approach:

{{< highlight c "linenos=table,hl_lines=2 5-6,linenostart=1" >}}
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

Let's go one line at a time as the code doesn't tell the whole story. First we load a piece of state based on `BusinessId` and `Id` of the message. What `LoadState` returns is either the newest version of the sate if a mesasge with `Id` has not been applied on the state yet **or the version proceeding the one which was the result of processing this message**. In other words, we are retrieving either the newest version or the version used to process the message the last time it was handled. From the calling code perspective these two scenarios can be deferentianted based on the `DuplicatedMessages` flag set by the state loading logic.

Next, the business logic gets invoked via `InvokeHandler` call which modifies the state and produces `outputMessages`. Finally, based on the `DuplciatedMessage` flag, we either store the state or skip it and later publish `outputMessages`. The concurrent modification of the state is handled by the `version` argument used for optimistic concurrency control.

### Implementation

TODO: link to repo and information on the technologies included

#### State management

With the general idea of the soutions let's look at the implementation details. We will use [EventSourcing](link) for storing the state as by definition it enables accessing historical versions of the state. More concretlly, we will use [StreamStone]() libarary which enables event sourcing over Azure TableStorage.

One of the outstading questions to answer is how does the state storage manage the connection between the message id and the version of the state that is requried. Here is a diagram that shows what is tha exactly gets stored in the event stream:

{{< figure src="/posts/state-based-storage-layout.png" title="Event sourced state with message processing metadata">}}

Every event that gets persisted includes additional metadata. Amongst others, this includes message id  


TODO: show code that retries the data and sets `Duplicated` flag.

#### Processing logic

TODO: show the handler logic and show why it needs to be deterministic
  * Discuss time, guid, random consideration


### Pattern
 * Context
 * Tradeoffs
 * Pros and cons



ToC:

 - What is consistent messaging? Two parts: state changes and output messages
 - Approach that assumes:
    - "Point-in-time" state availability (event sorucing is just one example)
    - Deterministic message handler logic
    - Concurrency control on the state changes
 - Algorithm
    - We have a sequence of states each state is "after-msg-x-being-processed"
    - We extend the state with message logical id,
    - When a message arrives we check if it's already been processed
 - Most interesting code fragments
    - How we invoke the handler and operate over event sourced data
 - Summary
    - Context:
    - Pros:
    - Cons:
 - Stay tuned


[^1]: 