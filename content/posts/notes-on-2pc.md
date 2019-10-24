---
layout: post
title: Notes on 2PC
date: 2019-09-04
draft: true
---

If there's a distributed protocol every software engineer knows it's Two-Phase Commit aka. 2PC. Although, in use for several decades[^1], it's application has been in decline for some time now - mainly due lack of support in the cloud. For quite a long time it has been a de-facto standard for building enterprise distributed systems. With the cloud becoming the default deployment option designers need to build reliable systems without 2PC. 

Answering the question how 2PC can be replaced requires understanding of what was it, that the protocol provided in he first place. In spite of its popularity, there is plenty of misconceptions around 2PC. This posts aims to clarify at least some of these.      

This is not "yet another introduction to 2PC"(TM). If you need a refresher read one of many descriptions out there[^1] before continuing.

### 2PC does not provide "transactions"
2PC is an atomic commit protocol meaning all participants will **eventually commit** if all voted "YES" - No more, no less than that. 

Let's look at an example to see what we mean by "no transactions". In our scenario we have two participants: a database and a messages queue. 

{{< figure src="/posts/2pc-atomic-visibility-scenario.jpg" title="2PC atomic visibility">}}

The diagram shows the part of the 2PC protocol after both participants voted "YES" and the cooridator is committing.  In our example, the queue transaction commits first however 2PC says nothing about order in which the participants commit or the delays between the commits. In other words, it is not deterministic.

What's most interesting is the ouside observer i.e. the client. It makes a read requests to both participants. In case of the message queue, the read request arrives after the commit from the coordinator. This means that the read operation will return any messages send to the queue as part of the transaction that just comitted. 

In case of the database the read request arrives before the commit. What will be the result here? First, 2PC says nothing about read behavior - it's outside of the system model defined by the protocol. The only requirement is that the database guarantees successful commit. 

The result of the read operation depends on the deployment configuration and there are at least two possible behaviors. The the read operation can:
    
* Block until the local transaction is committed - this will happen when local transaction operates in `Serializable` isolation level. This is default with Microsoft Distributed Transaction Coordinator (MSDTC, an implementation of 2PC built into Windows) and Microsoft SQL Server, but can be changed on a per-transaction basis.
* Return the last commited value (different from the one written by the local transaction) - this will happen when local transaction operates with `Snapshot` isolation.

In summary, 2PC does not provide atomic visibility of writes in a system when there are transactions committed with 2PC and other local transactions running at the level of each participant. Concrete behavior is not dictated by 2PC, though, but depends on the concrete implementation of the protocol, resources involved, as well as deployment and runtime configuration.

### 2PC can be high available
Any non-trivial protocol defines failure conditions that it's able to tolerate and 2PC is no exception. What is specific to 2PC is that some types of failures can make participants get "stuck". Whenever a participant votes "YES" it's unable to make any progress until hearing back from the coordinator. 

What are concrete reasons for getting stuck? First, the coordinator may fail. Secondly, the coordinator might be partitioned from the participant[^3]. The likelyhood of stucking is conditioned by coordinators availability and the probability of network partition. By making the failures less likely we can make 2PC more avaialble.

{{< figure src="/posts/2pc-no-progress.jpg" title="Participant in the 'stuck' state">}}

This touches on implementation and configuration argument already mentioned. For example in the MS DTC, the coordinator is a single process, but can be deployed in a fail-over cluster mode. That is a a deployment decision. There also nothing in 2PC that prevents the coordinator to be implemented as a quorum of process[^4]. 

Secondly, if all the parties (the coordinator and all the participants) are running in the same local network, on a single cluster or inside a single VM, than what is the probability of network partitioning? As always, context is king.   

### Commit latency is not the biggest problem
Commiting in 2PC requires 2 round trips between coordinator and participants, and there are 4*n messages generated, where n is the number of participants. This is sometimes viewed as the root cause of many practical problems with the protocol. It defenatelly isn't ideal but it only surfaces other, bigger problem.

The problem is potential contention at participant level caused by locking, especially in case of relational databases. Holding locks means that other transactions dealing with a given piece of state need to wait for the transaction to commit to make any progress.

This behavior exists without 2PC but the protocol makes is pretty much always worst as in 2PC the time the locks are held is defined by the slowest participant.

### 2PC fits the cloud quite well
We know that 2PC is used by the cloud vendors inside their services[^4] and can be used by the users when running at the level of IaaS[^5]. That said, none of the cloud vendors support MSDTC and/or XA at the level of native cloud services i.e. native service can't participante in 2PC. 

Often times, availability and performance are claimed to be the reasons for that. Although these two are definitely the strongest points of 2PC, it can be argued that security (or its lack) is even more important. 2PC assumes high degree of trust between the participants and the coordinator. One could imagine an evil user that uses a specially crafted coordinator to exhausts participants resources by purposefully letting transactions hang in the `stuck state`.

From the cloud vendor perspective that could have quite a damaging consequences. According to the protocol participant is not able to make any progress after voting "YES". So in case of malacious coordinator they would have to break the protocol or let their resources be blocked. Enabling cloud services to act as MSDTC participants is effectivelly opening doors for DoS attack[^6]. 

Even if the cloud vendors provided their own coordinators as the only valid option, a malacious participant could do still cause a lot of harm. 

### 2PC is not the only commit protocol
2PC is just one possible solution to atomic commit. It works well in certain scenarios but performs poorly when used in an environment that violates its assumptions.

Speaking of assumptions, 2PC assumes really little about transaction participants. Making more strict assumptions around transaction determinism allows for different approaches that minimize the lock holding time [^7]. 

It's even possible to remove the need for coordiantor if commit success is always possible due to the very nature of the resouces involved[^8].   

## Summary
Hopefully, this post puts a bit more light on 2PC and what is it that we get from the protocol. Although the era of 2PC is coming to an end, it's good to know what guarantees we need to provide by other means in the systems we build. 

[^1]: link to System R publication
[^2]: link to some decent 2PC tutorial
[^3]: note on cooperative commit option
[^4]: this is exactly what Google Spanner does [TODO-link]
[^5]: Azure connected services
[^6]: "(...) Ultimately, MSDTC is a single-node/cluster and local-network technology, which also manifests in its security model that is fairly difficult to adapt to a multitenant cloud system. (...)" by Clemens Vasters in [Distributed Transactions and Virtualization](http://vasters.com/archive/Distributed-Transactions-And-Virtualization.html)
[^7]: transactions in [FaunaDB](https://fauna.com/blog/consistency-without-clocks-faunadb-transaction-protocol) being a good example  
[^8]: Outbox pattern is commit protocol implementaiton that assumes writing to the message queue is idempotent and will always succeed
[^9]: windows clustering
