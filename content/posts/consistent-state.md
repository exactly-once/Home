---
layout: post
title: Consistent state
date: 2019-09-04
draft: true
---

One of the previous [posts](consistent-messaging.md) talked about exectly-once processing looking at the endpoint from the outside. Here we will re-focus on an individual endpoint and see what exactly-once means for an endpoint's state.

### It's about state not the execution history

Exactly-once spawed some heated debates in the past[^1] so let's make sure we make it clear what it means in our context - or more importantly what it doesn't. Here we talk about exactly-once **processing** not **delivery**, the two being quite different things.

The bad news is that exactly-once message **delivery** is not possible in a distributed system [^2]. The good news is that we don't need it to build roboust solutions. As long as the state is consistent (more on that in a second) we don't care about the message deilvery and endpoint execution history. 

The side-effects of message processing inside an endpoint are reflected in the state it manages. Messages being delivered to an endpoint and processed multiple times (message duplication) are not a problem as long as the state changes as if each logical message was processed exactly once. 

Let's look at a simple endpoint that stores items in order of their processing:

{{< figure src="/posts/consistent-state.jpg" title="Consistent state updates">}}

If there are multiple messages in-flight, there are many possible executions (depending failures, concurrency etc.) but the end state always refects **some** logical exactly-once execution. In other words we always end-up with some consistent state.

It's important to note that there is no single "state". Pretty much in any scenario there are multiple resource types used by an endpoint and not all resources are equal from the business perspective. Consistent, exactly-once message processing is a must for same e.g. relational databases storing business data. For others, like log files or performance metrics some inconsistency is tolerable. 

What this means is that we need to choose for which resources exactly-once consistency is needed. As ususal this is mainly business level decission. 

### Consistency inside out

Now that we know what it means for an endpoint to be conistent on the [outside](consistent-messaging.md) and from the inside, it's natural to ask how the two relate to each other. First, the state and messaging must reflect the same logical processing order. We need this to make sure that the messaging and state updates align in terms of the message order, and the data that gets written to the state and published in the messages. 

Secondly, we don't need the state and external messaging to be atomically vissible. We don't need the state updates and messages be avialble at once. It's fine if the state is updated before the messages are published or the other way round.

### Summary

TODO

[^1]: https://bravenewgeek.com/you-cannot-have-exactly-once-delivery/ and https://www.confluent.io/blog/exactly-once-semantics-are-possible-heres-how-apache-kafka-does-it/
[^2]: assuming asynchronous model where there are no bounds on message delivery delays [TODO: more meat needed here]
