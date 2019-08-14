---
title:
---

TL;DR; Idempotency is not enough to build robust distributed systems. It encourages looking at the system through the lense of individual operations which is only part of the story. It's interactions and protocols that drive changes in distributed systems and those are building blocks one should focus on.

# Introduction

Idempotency is often claimed to be a remedy for hard reality of distributed systems as if it was enough to make each and every operation idempotent to end-up with a robust solution. Practice proves to be more complex and when you scratch the surface this over simplistic view breaks apart.     

# Unboxing idempotency

There are many definitions of idempotency but the one probably most often used says that: 

> An operation `f` is idempotent if `f(f(x)) = f(x)`. 

Put differently, this means that no matter how many times the operation is applied on input `x` the outcome is the same as if the operation was performed only once. 

In order to get some intuition let's try to figure out what `f` and `x` stand for in practice. To cover different flavours of practical architectures let's assume that our system consists of number of endpoints. Each endpoint owns distinct piece of state and the only way for the endpoints to communicate is by sending messages. 

*Diagram*: endpoint with state that processes a message multiple times

In this context `x` is the state owned by the endpoint and `f` is logic executed as a result of processing a message. If `f` is idempotent then processing same message multiple times in succession (by definition) doesn't make a difference. This looks very useful considering the fact that most of today's communication infrastructures (HTTP, AMQP etc.) provide at-least-once message delivery guarantees.

What this reasoning hides is very often invalid assumption that there is well defined order in message delivery.

# Measuring temperature

Let's start with simple system consisting of two endpoints - one publishing `TemperatureMeasured: {double: Value}` events and the other that subscribes to those events and stores most up to date value. Processing each event at the subscriber executes following piece of logic:

``` C#
void Handle(TemperatureMeasured @event)
{
    this.Temperature = @event.Value;
}
```

The operation for handling `TemperatureMeasured` command is obviously idempotent - processing the same event multiple times in succession is equivalent to pressing it exactly once. 

But what happens if a given event gets processed more than once, interleaved with some other event? In such case, idempotency is not enough to make sure the most up-to-date measurement gets stored. It might happen that the older measurement gets reprocessed after a newer one already arrived which results in old value being stored. In practice such re-ordering is quite common and can happen for numerous reasons e.g. infrastructure re-delivery, sender buffering, receiver multi-threading just to name few possibilities.

This example shows that even in trivial systems, making operation idempotent doesn't solve problems caused by at-least-once message delivery. What we need are changes to the protocol. We could modify the interaction to make it request-response making the source endpoint re-send the same request until acknowledgement from the destination arrives. Alternatively, we could extend the event with a monotonous timestamp generated at the source and update the state of the subscriber only when timestamp in received message is greater than the last seen:

``` C#
void Handle(TemperatureMeasured @event)
{
    if(this.LatestTimestamp < @event.Timestamp)
    {
        this.Temperature = @event.Value;
        this.LatestTimestamp = @event.Timestamp;
    }
}
```

# Coupons for everybody

Imagine that at the end of each month we want to give out 10 USD gift cards to all our customers that made purchases for total of at least 1000 USD. There are `PurchaseMade : { guid: CustomerId, decimal: Amount }` events published in our system that hold the necessary information. What should be the logic for an endpoint that will process those events and control the generation process for the gift cards? 

The endpoint could hold a `CustomerId` to `TotalAmount` mapping and increase the `TotalAmount` with each `PurchaseMade` event. Is this idempotent? No. If the event gets reprocessed the `TotalAmount` value gets incorrectly increased. We can make the handling operation idempotent if the publishing event gets extended with unique identifier for each purchase made i.e. by adding `{ guid: PurchaseId }` to the published event. Now the endpoint holds the `CustomerId` to `TotalAmount` mapping and a collection of all purchase orders and `TotalAmount` gets increased only if the `PurchaseIds` collection doesn't hold the identifier in the message that is processed. 

This looks good until we examine what happens at the end of each month when `MonthElapsed : { int: Year, int: Month }` gets published and processed by our endpoint. At first sight the logic looks quite simple i.e. `MonthElapsed` event handling logic checks the current `TotalAmount` if it's greater than 1000 USD a gift card generation gets scheduled. Secondly no matter what `TotalAmount` is set to `0` and `PurchaseIds` collection gets cleared. 

Both operations, the one for handling `PurchaseMade` event and the other for `MonthElapsed` are idempotent, still we end-up with logic which is clearly broken. What happens if a customer makes a purchase just at the end of the month? What if there where payment problems and the `PurchaseMade` event got published a week after the business action was performed? Well, it means that some of the `PurchaseMade` events for a given month can arrive at the endpoint after `MonthElapsed`!   




* customer payment history case


Move arm to the position. Ideal case. Sender synchronization. How this breaks in failure situations (diagram based on endpoint state evolution).

Show some code
 
# How to solve this peak 
Future:  
 * Protocol has to deal with re-orderings. Synchronization points. Sender epochs. Compensating actions.
 * Idempotency is non trivial - what is that the infrastructure can do for you.

Content:
 - Reality of message processing duplication and re-ordering
 - Assumptions about the endpoints
 - Unboxing definition of idempotency
 - Where it all breaks
 - How to make it work again