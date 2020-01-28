---
layout: post
title: State-based consistent messaging
date: 
---

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

In the previous posts we described cosistent messaging and justified it's usefulness in building robust distributed systems. Enough with theory, it's high time to show some code! First comes the state-based approach.

## Assumptions

The state-based approach to consistent messaging comes with few assumptions:

* "Point-in-time" state availability - it is possible to restore historical version on the endpoints state
* Mesage processing logic is deterministic - for a given state version and input message the endpoint will always produce the same changes (state modifications and output messages)
* The state storage provides concurrency control - the store used for enpoint state enables handling "concurrent write" conflicts

## Idea

What we want to do is make sure that any message gets applied on the state at most once and secondly that message duplicates produce the same output messages on re-processing. Our assumptions already give us rough idea on the algorithm for consistent message processing:


```C# {linenos=table,hl_lines=[8,"15-17"],linenostart=199}
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
```

Let's go one line at a time as the code doesn't tell the whole story. First we load a piece of state based on `BusinessId` and `Id` of the message. What `LoadState` returns is either the newest version of the sate if a mesasge with `Id` has not been applied on the state yet **or the version proceeding the one which was the result of processing this message**. In other words, we are retrieving either newest versoin or the exact version used to process this message the last time it was handled. From the calling code perspective these two scenarios can be deferentianted based on the `DuplicatedMessages` flag set by the state loading logic.

Next, the business logic gets invoked via `InvokeHandler` call which modifies the state and produces `outputMessages`. Finally, based on the `DuplciatedMessage` flag, storing state changes might be skipped and `outputMessages` are published. The concurent modification of the state is handled by the `version` argument which is used for optimistic concurrency control.

### Implementation

TODO: Diagram

* Event sourcing
* Show a handler 
  * Discuss time, guid, random consideration


### Pattern
 * Context
 * Tradeoffs
 * Pros and cons






[^1]: 