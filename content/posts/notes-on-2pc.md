---
layout: post
title: Notes on 2PC
date: 2019-09-04
draft: true
---

If there's one protocol every distributed system's engineer knows it's Two-Phase Commit (2PC). That said the understanding often doesn't match the popularity. In this post we will discuss selected misconceptions around 2PC. This is not yet another description of 2PC (TM) - if you need a refresher you might want to read one of the articles on 2PC. TODO:(link-to-2pc-description).

### 2PC == MSDTC
MSDTC (or XA if you come from the Java space) is 2PC coordinator implementation - one of many possible. It comes with concepts like `TransactionManagers` and `ResourceManagers`, implements security between parts of the system and provides tooling to figure out what's going on. Finally, it requires that `ResourceManagers` (aka. participants) support distributed transactions in order to take part in the protocol.

You might find this distinction pedantic but as we will soon see it's important to make it clear if we talk about MSDTC or 2PC.

### 2PC applies to databases only
2PC tells nothing about resources participating in the protocol. In MSDTC those could be databases, queueing systems, Web Services, files systems or any other resource that as long as they implement the protocol .

### 2PC provides atomic visibility
2PC ensures all participants will eventually commit i.e it is an atomic commit protocol. It **doesn't** however provide atomic visibility. When a transaction is being committed, it's possible to observe partial results.

Imagine scenario, with 2PC spanning two databases. There is nothing that prevents a client from querying both databases and see one database before and the other after the commit. Finally, the order of commits is un-deterministic and can't be controlled.

[TODO: diagram]

If you come from the C# world and wonder why you haven't seen this happening in practice remember that 2PC != MSDTC. As any concrete implementation `System.Transactions.TransactionScope` used from managing MSDTC transactions comes with default configuration. Specifically, it uses `Serializable` as default isolation level. What it means for our scenario is that a client can't make a read from any database until the transaction commits (as the committing transactions are holding exclusive locks). Obviously, this doesn't hold for resources that don't support `Serializable` isolation levels or when you change the default configuration.

### 2PC is not fault tolerant
Resources participating in 2PC can't make progress *on-their-own* if they voted `Yes` and are waiting for `Coordinators` decision. In other words it is possible for a participant to get stuck until hearing back from the coordinator. Looking at a sample code it means that provided `scope.Compete` has been called and we are leaving the `using` scope (this is when MSDTC commit is triggered) than the transaction can get stuck if the coordinator fails midway transaction commit.

That said we are talking here about MSDTC which only one possible 2PC implementations. There is nothing that prevents us from running coordinator over some fault tolerant protocol. If we combine that with highly available network  making network partitioning highly unlikely we end-up with pretty robust solution. In fact this exactly how Google Spanner is internally using 2PC (TODO: link).

### 2PC's biggest problem is commit latency
It's not the latency but 

### 2PC is unsuitable for Cloud
We already know that it's used in the cloud (Spanner) and can be used by the users for some time already (VMs etc.). What it does, is that it assumes full trust between processes which is not the case in cloud environment.

Who are participants? If we expose 2pc to the clients they can do DOS.

### 2PC is the only commit protocol out-there
No! E.g. FaunaDB.

## Summary
I hope this post puts some light on 2PC and it's characteristics necessary to make an informed  judgement on it's suitability for given context.  