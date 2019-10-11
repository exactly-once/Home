---
layout: post
title: Consistent state
date: 2019-10-11
draft: false
---

In the previous [post](/posts/consistent-messaging) we talked about exactly-once processing looking at the endpoint from the outside. Here we will re-focus on an individual endpoint and see what exactly-once means for an endpoint's state.

### It's not about the execution history

Exactly-once spawned some heated debates in the past[^1] so let's make sure we make it clear what it means in our context - or more importantly what it doesn't. Here we talk about exactly-once **processing** not **delivery**, the two being quite different things.

The bad news is that exactly-once message **delivery** is not possible in a distributed system [^2]. The good news is that we don't need it to build robust solutions. As long as the state is consistent (more on that in a second) we don't care about the message delivery and endpoint execution history.  

Let's look at a simple endpoint that stores items in order of their processing:

{{< figure src="/posts/consistent-state.jpg" title="Consistent state updates">}}

In any scenario with multiple messages in-flight, there are many possible executions (depending on failures, concurrency, etc.). That said, if updated consistently, the end state always refects **some** logical exactly-once execution. Messages being delivered to an endpoint possibly multiple times are not a problem as long as the state changes as if each logical message was processed exactly once.

It's important to note that there is no single "state". Pretty much in any scenario, there are multiple resource types used by an endpoint and not all resources are equally important. Consistent, exactly-once message processing might be a must for the same e.g. relational databases storing business data. For others, like log files or performance metrics some inconsistency is tolerable. 

What this means is that we have to choose which resources need exactly-once. In many cases, this is a business-level decision. 

### Consistency inside out

Now that we know what it means for an endpoint to be consistent on the [outside](consistent-messaging.md) and from the inside, it's natural to ask how the two relate to each other. 

First, the state and messaging must reflect the same logical processing order. We need this to make sure that the messaging and state updates align in terms of the message order, and that the data written to the state and published in the messages do not contradict each other. 

Secondly, we don't need the state and external messaging to be atomically visible. It's fine if the state is updated before the messages are published or the other way round.

### Summary

It's one thing to know what is needed and another to design and build it. In the following parts of this series, we will look at the design aspects of exactly-once message processing. Stay tuned!   

[^1]: Valuable discussion is hard, especially when talking about two different things
[^2]: [You Cannot Have Exactly-Once Delivery](https://bravenewgeek.com/you-cannot-have-exactly-once-delivery/) is an overview of the subject
