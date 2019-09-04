---
layout: post
title: Consistent messaging
date: 2019-09-04

---

Modern messaging infrastructures offer delivery guarantees that make it non-trivial to build distributed systems. Robust solutions require a good understanding of what can and can't happen in a system and how that affects business level behavior.

This post walks through scenarios that look at the main challenges from the system consistency perspective and sketches possible solutions. 
 
## A system 

We will assume that systems in focus consist of endpoints, each owning a distinct piece of state. Every endpoint processes input messages, modifying its internal state and producing output messages. All endpoints communicate using persistent messaging with at-least-once delivery guarantee. Finally, we will assume that no messages can be lost.

This covers a pretty wide range of systems. Most notably service-based architectures build on top of modern messaging infrastructure - both on-premise and in the cloud [^1]. 

{{< figure src="/docs/an_endpoint.jpg" title="An endpoint">}}

With at-least-once delivery, any in-flight message gets delivered possibly multiple times. This is a direct consequence of communication protocols used as any message will be re-delivered until it gets acknowledged by the receiver. Duplicates are also created on the producer side as the producer needs to retry sending messages until it gets an acknowledgement from the infrastructure. 

Apart from being duplicated, in-flight messages can get re-ordered. There are many reasons for this to happen [^2] one of the most obvious being message re-delivery mechanism. If delivery fails, a message is available for reprocessing only after some back-off period. Any other in-flight message can be processed during that time causing the respective order of those messages to change.

When combined, duplication and re-ordering can produce, at the receiver side, any sequence of messages. The only guarantee is that the resulting sequence contains at least one copy of each message sent. 

{{< figure src="/docs/in_flight-to-processing_order.jpg" title="Sample duplication and re-ordering scenarios">}}

## The system

Let's look at a system that models a moving target shooting range to see the practical consequences of this behavior. 

We will start with a single `ShootingRange` endpoint which stores shooting target's location `{ int: TargetPosition }` and processes `FireAt : { int: Position }` messages. 

Whenever `FireAt` message gets processed the endpoint produces either `Hit` or `Missed` event to indicate the result:

{{< highlight csharp >}}
void Handle(FireAt message)
{
 if(this.TargetPosition == message.Position) 
 {
 Publish(new Hit());
 }
 else 
 {
 Publish(new Missed());
 }
}
{{< /highlight >}}

### Duplicates

Let's extend the system with a second `LeaderBoard` endpoint that's responsible for storing the number of target hits that the player made. The endpoint processes `Hit` messages generated by the `ShootingRange`:

{{< highlight csharp >}}
void Handle(Hit message)
{
 this.NumberOfHits++;
}
{{< /highlight >}}

It's easy to notice that this will break when `Hit` messages get duplicated. When `LeaderBoard` receives a `Hit` message it has no way to tell if there's been a new hit or if it's just duplicate of some other `Hit` message already processed.

The only way to cope with duplicates is by making sure we can test message equality at the business level. This can be achieved by modeling messages as immutable facts or intents with **unique identity** rather than values [^3].

If we extend `FireAt` message with `AttemptId` property (unique for each attempt the player makes) we can later use it as an identifier for the `Hit` event. With that in place `LeaderBoard` logic becomes:

{{< highlight csharp >}}
void Handle(Hit message)
{
 if(this.Hits.Contains(message.AttemptId))
 {
 return;
 }
 this.Hits.Add(message.AttemptId);
 
 this.NumberOfHits++;
}
{{< /highlight >}}

In short, business-level identifiers are a must to cope with duplicates.

### Re-ordering

Let's add another moving piece to our system - `GameScenario` endpoint that changes current position of the moving target by sending `MoveTarget` messages to the `ShootingRange` endpoint. `ShootingRange` logic now becomes:

{{< highlight csharp >}}
void Handle(MoveTarget message)
{
 this.TargetPosition = message.Position;
}

void Handle(FireAt message)
{
 if(this.TargetPosition == message.Position) 
 {
 Publish(new Hit { AttemptId = message.AttemptId });
 }
 else
 {
 Publish(new Missed { AttemptId = message.AttemptId });
 } 
}
{{< /highlight >}}

Let's analyze one possible processing scenario that incudes `FireAt` and `MoveTarget` messages. We begin with `TargetPosition` equal to `42`, the player sends `FireAt : { Position: 42 }` and `GameScenario` sends `MoveTarget : {Position: 1}`. Due to duplication and re-ordering `FireAt` gets processed first followed by `MoveTarget` and finally `FireAt` duplicate. 

{{< figure src="/docs/seq-consistency-corruption.png" title="An 'alternative worlds' scenario">}}

This results with `ShootingRange` publishing two events - `Hit` and `Missed`, both for the same `FireAt` message. 

**We ended up with two messages representing two contradictory facts about the same attempt**. It's not the case of an unexpected end-state e.g. with an attempt resulting in a miss when we expected a hit. It's far worse than that! We ended up in a state which indicates that two logically exclusive alternatives occurred. A state which is simply corrupted.

## Consistency

We know things went bad but what was the root cause? It all boils down to the fact that `FireAt` duplicate was processed using a different version of `ShootingRage` state than the first time. Initially, `TargetPosition` was `42` and changed to `1` before the duplicate arrived. That, in turn, resulted in "alternative-worlds" scenario where the attempt both missed and hit the target.

Duplicates and re-ordering are the reality we operate in and can't change. What we can do though, is to ensure that once a message gets processed all duplicates result in consistent observable side-effects i.e. messages produced. In our example, we need a guarantee that processing `FireAt` duplicate results either in no messages published or in an exact copy of the first `Hit` event. Producing duplicates is fine as those have to be handled either way. 

More generally, we want an endpoint to produce observable side-effects **equivalent to some execution in which each logical message gets processed exactly-once**. Equivalent meaning that it's indistinguishable from the perspective of any other endpoint.

## Exactly-once

There are many possible implementations of exactly-once behavior. Every with its own set of constraints and trade-offs. As usual, which approach is the best fit depends on the context and concrete requirements. 

### Business logic level

It's possible to make the business logic responsible for producing consistent behavior. In such a case, the business rules have to be extended or tweaked to make sure duplicates and re-ordering are properly handled. 


### State-based

Any operation performed on the same input (state) results in the same output (messages), no matter how many times executed. If for any duplicate we could get a version of the state as it was when the first processing happened than we could re-run the handling logic and be sure to get consistent output.

### Side-effects based

Alternatively, we could capture the side-effects instead of the state used to produce them. What gets captured in such an approach are not the historical versions of the state but rather messages that got produced when processing a given message. 

With that in place, whenever a message arrives we can query the side-effects store to see if that's a duplicate. If so, the business logic invocation can be skipped and the stored messages published right away. 

## Summary

There are non-trivial challenges that designers need to overcome when building message-based systems. In this post, we've seen what kind of consistency problems may arise when message duplication and re-ordering are not handled with care. Finally, we sketched some of the possible ways to ensure consistent business behavior.

That being said we only scratched the surface. There are many architectural and technical aspects that we did not consider tough: What can be done generically, independent of the business logic? Do we require any guarantees from the storage used by the endpoint? Exactly, how much extra data do we need to store? 

Those are all interesting topics that we will be covered in the follow-up posts.

[^1]: RabbitMQ, ASQ, Azure Service Bus, SQS are just a few examples
[^2]: Great description of ordered delivery challenges can be found in [Kevin's](https://sookocheff.com/post/messaging/dissecting-sqs-fifo-queues/) post. The post focuses on SQS but drives to conclusions applicable to other messaging solutions out there.
[^3]: Similarly to Value Objects and Entities in Domain-Driven Design