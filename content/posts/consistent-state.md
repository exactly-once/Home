---
layout: post
title: Consistent state
date: 2019-09-04
draft: true
---

ToC:
 * we defined exactly-once from the external observer's perspective
 * here we will look at it from the endpoint state's perspective
 * Not all state is made equal - logs vs business data
 * State can't reflect process execution history
 * We need to decide where we can tolerate duplication and where exactly-once is needed

One of the previous [posts](consistent-messaging.md) talked about exectly-once message looking at the endpoint from the outside. Here we will re-focus on an individual endpoint and see what exactly-once means for an endpoint's state.

### It's about state not the execution history
Exactly-once spawed some heated debates in the past[^1] so let's make sure we make it clear what it means in our context-  or even more importantly what it doesn't. Here we talk about exactly-once **processing** and not **delivery** the two being quite different things.

The bad news is that exactly-once message **delivery** is not possible in a distributed system [^2]. The good news is that we don't need it to build roboust distributed systems. What we usually care the most in our systems is the state. As long as the state is consistent (more on that in a second) we don't care about the message deilvery and process execution history. 

TODO: example of a single message processed 3 times with transaction succeeding on the last attemp. State is a record or processing history that is derivative of message delivery history but not one-to-one mapping!

### There is no state

TODO: not all state is made equal and we don't care about all the sate in the same manner. Business state is high prio. Loggin/tracing is not that important in most of the domains.


[^1]: https://bravenewgeek.com/you-cannot-have-exactly-once-delivery/ and https://www.confluent.io/blog/exactly-once-semantics-are-possible-heres-how-apache-kafka-does-it/
[^2]: assuming asynchronous model where there are no bounds on message delivery delays [TODO: more meat needed here]