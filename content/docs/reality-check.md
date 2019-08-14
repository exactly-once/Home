## Introduction

Building message-based systems requires understanding the guarantees provided by the infrastructure. Only then is it possible to identify what can be solved for us and what requires dedicated logic.

Historically, Two-Phase-Commit protocol with MS DTC implementation on Microsoft stack and XA in the Java world made the default baseline for building messaging systems. This enabled queue and SQL operations to be performed in an atomic manner. For number of reasons (*) this changed quite a bit. At-lest-once message delivery is the de-facto standard and should be assumed from modern messaging infrastructures, both in the cloud (Azure ServiceBus, Amazon SQS) as well on on-prem (RabbitMQ, ActiveMQ)
   
## Duplicates

At-least-once message delivery means that (no surprise here) any message gets delivered - possibly multiple times. This is a direct consequence of protocols used for infrastructure-to-receiver communication. A message will be redeliver until it gets acknowledged by the receiver. Even if the receiver got the message and processed it successfully but the acknowledgement did not make it back to the infrastructure, the message will be re-delivered. Duplicates become an obvious consequence of this behavior. 

What might be a bit less expected is that duplicates get generated also when messages get sent. Any producer can't assume that a message has been delivered and stored by the infrastructure until it gets an acknowledgement. As a result it might need to re-send a message, possibly creating duplicates.

## Re-ordering 
 * Multi-threading
 * Retires
 * Dead-lettering
 * SQS and availability
 * Sessions - link to a post by the gu

