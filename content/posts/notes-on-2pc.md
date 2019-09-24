---
layout: post
title: Notes on 2PC
date: 2019-09-04
draft: true
---

If there's one protocol every distributed system's engineer knows it's probably Two-Phase Commit (2PC). That said the understanding often doesn't match the popularity. In this post will discuss misconceptions around 2PC that we have encountered. This is not yet another description of 2PC (TM) - if you need a refresher you might want to read [this](link-to-2pc-description).

### 2PC == MS DTC
MS DTC (or XA if you come from the Java space) is an implementation of 2PC - one of many possible. Among others, it comes with concepts like `TransactionManagers` and `ResourceManagers`, implements security between parts of the system and provides tooling to figure out what's going on in your system. As we will soon see it's important to make it clear if we talk about MS DTC or 2PC.

### 2PC applies to databases only
2PC tells nothing about resources participating in the protocol. In MS DTC those could be databases, queueing systems, Web Services etc.

### 2PC provides atomic visibility
2PC is an atomic commit protocol meaning that all participants will eventually commit. It **does not** provide atomic visibility i.e. making sure that it's impossible to see partial commit results.  

Two databases in snapshot isolation mode and reads from one and the other. 

Indicate difference between MS DTC (with default configuration) and 2PC.

### 2PC does not tolerate failures
Participants can't make progress *on-their-own* when waiting for `Coordinators` decision. That being said that *window* of vulnerability is smaller than some might think (only during voting not during performing transactional work on each resource).

Coordinator is a single point of failure but we can make it more fault tolerant! e.g. spanner's case. 

Talking of implementation: "Is your DB more fault tolerant than your transaction coordinator?".

### 2PC's biggest problem is commit latency
It's not the latency but 

### 2PC is unsuitable for Cloud
We already know that it's used in the cloud (Spanner) and can be used by the users for some time already (VMs etc.). What it does, is that it assumes full trust between processes which is not the case in cloud environment.

Who are participants? If we expose 2pc to the clients they can do DOS.

### 2PC is the only commit protocol out-there
No! E.g. FaunaDB.

## Summary
I hope this post puts some light on 2PC and it's characteristics necessary to make an informed  judgement on it's suitability for given context.  