---
title: The problems
bookShowToc: true
---

# The problems

Historically, at-least-once delivery and lack of transactional guarantees weren't that big of a problem. Widespread adaptation of Two-Phase-Commit protocol with MS DTC implementation on Microsoft stack and XA in the Java world made things simple. In most of the cases, system builders only had to make sure transactions span a messaging infrastructure and a relational database used by their services. 

With the dawn of Cloud that changed quite a bit. For various reasons (ref: Vasters) support for Two-Phase-Commit is not (and very likely never will be) supported by cloud native messaging infrastructure. Secondly, the era of polyglot persistence introduced a whole spectrum of transactional guarantees at the storage level - very often weaker than default isolation modes used in RDMS. 

The current reality of any system builder is that they need to cope with at-least-once delivery and lack of transactions in one way or the other. Either using homegrown solutions or using frameworks and/or platforms available on the market. 

No matter the route, the knowledge of available solutions proves to be quite useful when building message-based distributed systems. That said the understand of the solutions start with understanding the problems.

## At-least-once message delivery

At-least-once message delivery is de-facto standard for modern messaging infrastructures, both in the cloud (Azure ServiceBus, Amazon SQS) as well as on-prem (RabbitMQ, ActiveMQ). At-least-once message delivery means that (no surprise here) any message eventually gets delivered - possibly multiple times. This is a direct consequence of a mechanism used for infrastructure-to-message-receiver communication - the infrastructure will redeliver a message until it gets acknowledged.

At the system design level this causes obvious trouble. Messages flowing in the system represent intents or facts from the business domain that mustn't get processed multiple times. Charging a customer for an order once is very different from charging her twice or ten times! The workings of messaging infrastructure is not going to change any times soon which means that unwanted consequences of at-least-once delivery have to be coped with on the receiving end.

## No-transactions

In a message-based system the state evolves with each message being processed. A message lands in a queue, a receiver picks the message and acts on it making changes to it's internal state and possibly publishing new messages. There are two resources at play here: the storage used for business data and the messaging infrastructure. At the business domain level all those operations are an atomic unit - either all should succeed or none. 2PC protocol solved just that, it provided an atomicity guarantee for the logical operations spanning multiple resources. With 2PC gone this has to be provided in some other way. 

## Anomalies
  
We already talked about possible anomalies caused by at-least-once message delivery - business actions get triggered multiple times duplicating actions that should happen only once. 

Lack of atomicity means that we can end-up with partial change application. In most general case the set of operations consists of business data modifications, input message acknowledgement, and number of send operations. Depending on implementation and failure scenario we can end-up with any subset of the operations being applied - no operations and all of them being special cases. 

Let's look into some of those scenarios more concretely.

 * Input message loss - when input message gets acknowledged and none of the other operations succeed as if input message got lost,
 * Output message loss - when some of the outgoing messages don't get sent,
 * Ghost messages - when some outgoing messages get sent but business data modifications fail,
 * Duplicates - when all operations succeed except input message acknowledgement which causes redelivery.
 
We already know what are potential consequences of message duplicates. Message loss scenarios can cause missing data as well as business processes getting stuck. Finally, ghost messages cause sate inconsistencies as a receiver of such messages acts on a piece of data that doesn't exist anywhere else. Imagine situation when an order is processed however (due to a failure) a ghost message is sent containing an if than never got to the business data storage.

TODO: realization. No-transactions force us to deal with duplicates => solving no-transactions solves at-least-once delivery anomalies





