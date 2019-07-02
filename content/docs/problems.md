---
bookShowToc: true
---

# The problems

Historically, at-least-once delivery and lack of transactional guarantees weren't that big of a problem. Widespread adaptation of Two-Phase-Commit protocol with MS DTC implementation on Microsoft stack and XA in the Java world made things simple. In most of the cases, system builders only had to make sure transactions span a messaging infrastructure and a relational database used by their services. With the dawn of Cloud that changed quite a bit. For various reasons (ref: Vasters) support for Two-Phase-Commit is not (and very likely never will) be supported by cloud native messaging infrastructure. Secondly, the era of polyglot persistence introduced a whole spectrum of transactional guarantees at the storage level - very often weaker than default isolation modes used in RDMS. 

The current reality of any system builder is that they need to cope with at-least-once delivery and lack of transactions in one way or the other - either using homegrown solutions on using frameworks and/or platforms available on the market. No matter the route the knowledge of the solutions proves to be quite useful when building message-based distributed systems. That said the understand of the solutions start with understanding the problems.

## At-least-once message delivery

At-least-once message delivery is de-facto standard for modern messaging infrastructures, both in the cloud (Azure ServiceBus, Amazon SQS) as well as on-prem (RabbitMQ, ActiveMQ). At-least-once message delivery means that (no surprise here) any message gets delivered. Possibly multiple times. This is a direct consequence of the protocol used between the infrastructure and message receiver - the infrastructure will redeliver a message until it gets acknowledged.

At the system design level this causes obvious trouble. Messages flowing in the system represent intents or facts from the business domain that mustn't get processed multiple times. Charging a customer for an order once is very different from charging her twice or ten times! The workings of messaging infrastructure is not going to change any times soon which means that unwanted consequences of at-least-once delivery have to be coped on the receiving end.

## No-transactions

In a message-based system the sate of the system evolves with each message being processed. A message lands in a queue, a receiver picks the message and acts on it making changes to it's internal state and possibly publishing new messages. There are two resources at play here: the service's storage and the messaging infrastructure. At the business domain level all those operations are an atomic unit - either all of should succeed or none. 2PC protocol solved just that, it provided an atomic guarantee for the logical operations spanning multiple resources. With 2PC gone the atomicity guarantee has to be provided in some other way. 