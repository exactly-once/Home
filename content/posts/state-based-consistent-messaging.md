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

## Goal

Before we delve into code it's good to remind what is the objective in terms of the desired behavior. First, we want and endpoint to produce consistent output messages:

> (...) we want an endpoint to produce observable side-effects **equivalent to some execution in which each logical message gets processed exactly-once**. Equivalent meaning that it's indistinguishable from the perspective of any other endpoint.

Secondly, we want endpoint's sate to change in a consistent manner:

> (...) the end state always refects **some** logical exactly-once execution. Messages being delivered to an endpoint possibly multiple times are not a problem as long as the state changes as if each logical message was processed exactly once.
 
Finally, whatever is the logial message processing order, the state and output messages histories must be the same:

> First, the state and messaging must reflect the same logical processing order. We need this to make sure that the messaging and state updates align in terms of the message order, and that the data written to the state and published in the messages do not contradict each other. 

## Assumptions

The state-based approach to consistent messaging comes with few assumptions:

* "Point-in-time" state availability - the way state is stores enables restoring historical version on the endpoints state
* Mesage processing logic is deterministic - for a given state version and input message the endpoint will always produce the same changes (state modifications and output messages)
* The state storage provides concurrency control - the store used for enpoint state enables handling "concurrent write" conflicts

[^1]: 