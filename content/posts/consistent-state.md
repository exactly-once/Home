---
layout: post
title: Consistent state
date: 2019-09-04
draft: true
---

One of the previous [posts](consistent-messaging.md) talked about exectly-once processing looking at the endpoint from the outside. Here we will re-focus on an individual endpoint and see what exactly-once means for an endpoint's state.

### It's about state not the execution history

Exactly-once spawed some heated debates in the past[^1] so let's make sure we make it clear what it means in our context -  or more importantly what it doesn't. Here we talk about exactly-once **processing** not **delivery**, the two being quite different things.

The bad news is that exactly-once message **delivery** is not possible in a distributed system [^2]. The good news is that we don't need it to build roboust solutions. As long as the state is consistent (more on that in a second) we don't care about the message deilvery and endpoint execution history. 

The side-effects of message processing inside an endpoint are reflected in the state it manages. Messages being delivered to an endpoint and processed multiple times (message duplication) are not a problem as long as the state changes as if each logical message was processed exactly once. 

Let's look at a simple e-commerce system that enables adding items to the user's basket:

{{< highlight csharp >}}
void Handle(AddItem message)
{
    if(this.Items.Contains(i => i == message.ItemId))
    {
        return;
    }

    this.Items.Add(message.ItemId);
}
{{< /highlight >}} 

If there are multiple messages in-flight depending on the order of delivery, failures, concurrency we may end-up with different logical message executions but the end state always refects some logical exactly-once executions.

Diagram: 


### There is no state

TODO: not all state is made equal and we don't care about all the sate in the same manner. Business state is high prio. Loggin/tracing is not that important in most of the domains.

### Consistency on the inside and on the outside

* There is not strict need to provide atomic visibility between the inside and outside consistency (2PC no order, outbox has order)
* We need the consistency between inside and the outside if a logica id is persited in the endpoint and in the messages they need to be the same

[^1]: https://bravenewgeek.com/you-cannot-have-exactly-once-delivery/ and https://www.confluent.io/blog/exactly-once-semantics-are-possible-heres-how-apache-kafka-does-it/
[^2]: assuming asynchronous model where there are no bounds on message delivery delays [TODO: more meat needed here]