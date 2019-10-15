---
layout: post
title: Notes on 2PC
date: 2019-09-04
draft: true
---

If there's a distributed protocol every software engineer knows it's Two-Phase Commit. It's been around for several decades now [^1], sadly, there are quite a few misunderstandings around 2PC that we encountred in our practice. 

This is not "yet another introduction to 2PC"(TM). If you need a refresher go through some the good [^2] descriptions of the protocol before continuing.

### 2PC != MS DTC
MS DTC (or XA if you come from the Java space) is an implementation of 2PC - one of many possible. It comes with concepts like `TransactionManagers` and `ResourceManagers`, implements security between participating processes, provides tooling to figure out what's going on in your system, etc.. 

### 2PC is not only about databases
2PC tells nothing about resources participating in the protocol. Some of the most widely available implementations like MS DTC or XA support databases, queueing systems and Web Services. In fact, the concrete protocols are open and anyone is free to create new implementations for other types of resources. 

### 2PC does not provide atomic visibility
2PC is an atomic commit protocol meaning all participants will **eventually commit** if all voted "YES". This however doesn't say anything about order in which the participants commit or the delays between commits.

Let's look at an example to see what we mean by lack of atomic visibility. In our scenario we have two participants: a database and a messages queue. 

{{< figure src="/posts/2pc-atomic-visibility-scenario.jpg" title="2PC atomic visibility">}}

The diagram shows the part of the 2PC protocol after both participants voted "YES" and the cooridantor is commiting. What's most interesting is the ouside observer i.e. the client. It makes a read requests to both participants. In case of the message queue, the read request arrives after the commit from the coordinator which means that this read will return any messages send to the queue. 

In case of the database the read request arrives before the commit. What will be the result here? First, 2PC says nothing about read behavior, it only requires that the database guarantees successful commit. The result depends on is the deployment configuration and there are at least two possible behaviors. The the read operation can:
    
* Hang until the local transaction is committed - this will happen when local transaction operates in `Serializable` isolation level. This is default with MS DTC and MS SqlServer unless explictly changed,
* Return the last commited value (not the one written by the local transaction) - this will happen when local transaction operates with `Snapshot` isolation.

Again. The behavior is not dictated by 2PC it depends on configuration of concrete implementation and configuration.

### 2PC is not fault tolerant enough
Any non-trivial protocol defines failure conditions that it's able to tolerate - 2PC is no exception. What is specific to 2PC is that some types of failures can make participants get "stuck". Whenever a participant votes "YES" it's unalbe to make any progress until hearing back from coordinator. 

What are concrete reasons for getting stuck? First, the coordinator may fail. Secondly, the coordinator might be partitioned from the participant[^3]. The likelyhood of stucking is conditioned by coordinators availability and the probability of network partition. Making coordinator and network more available we can make 2PC more fault tolerant.

{{< figure src="/posts/2pc-no-progress.jpg" title="Participant in the 'stuck' state">}}

This touches one more time on "2PC is not MS DTC". In MS DTC, the coordinator is a single process which is purely implementation decission. There is nothing in 2PC that could prevents us from implementing it as quorum of process[^4]. Secondly, if we run in a local network or inside a single VM (the coordinator and all participants) what is the probability of network partitioning? As always, context is the king.   

### 2PC's biggest problem is commit latency
It's not the latency but 

### 2PC is unsuitable for Cloud
We already know that it's used in the cloud (Spanner) and can be used by the users for some time already (VMs etc.). What it does, is that it assumes full trust between processes which is not the case in cloud environment.

Who are participants? If we expose 2pc to the clients they can do DOS.

### 2PC is the only commit protocol out-there
No! E.g. FaunaDB.

## Summary
I hope this post puts some light on 2PC and it's characteristics necessary to make an informed  judgement on it's suitability for given context.  

[^1]: link to System R publication
[^2]: link to some decent 2PC tutorial
[^3]: note on cooperative commit option
[^4]: this is exactly what Google Spanner does [TODO-link]
