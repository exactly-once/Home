---
layout: post
title: Notes on 2PC
date: 2019-10-24
draft: false
---

If there's a distributed protocol every software engineer knows it's Two-Phase Commit also know as 2PC. Although, in use for several decades[^1], it's been in steady decline mainly due to lack of support in cloud environments. 

For quite some time it was a de-facto standard for building enterprise distributed systems. That said, with the cloud becoming the default deployment model, designers need to learn how to build reliable systems without it. 

Answering the question of how 2PC can be replaced requires an understanding of what it was, that the protocol provided in the first place. In spite of its popularity, there are plenty of misconceptions around 2PC. This post aims to clarify at least some of these.      

NOTE: This is not "yet another introduction to 2PC"(TM). If you need a refresher read one of many descriptions out there before continuing.

### 2PC doesn't provide "transactions"
2PC is an atomic commit protocol meaning all participants will eventually commit if all voted "YES" or leave the system unchanged otherwise. When a commit operation triggered by the user finishes, either all local modifications have been applied or none of them has. The commit can take arbitrarily long to complete and in some failure scenarios, it will hang forever.

Let's look at an example to see what we mean by "no transactions". In our scenario, we have two participants: a database and a messages queue. The diagram shows 2PC execution after both participants voted "YES" and the coordinator is committing.

{{< figure src="/posts/2pc-atomic-visibility-scenario.jpg" title="2PC atomic visibility">}}

Our example assumes that the queue transaction commits first, however, 2PC says nothing about the order in which the participants commit. It is nondeterministic and can change for the same set of participants on each execution.

What's most interesting is the outside observer i.e. the client. It makes a read requests to both participants. The read request to the message queue arrives after the commit from the coordinator. This means that the read operation returns messages written to the queue in the transaction that just committed. 

In the case of the database, the read request arrives before the commit. What will be the result here? 2PC says nothing about this behavior - **it's outside of the system model defined by the protocol**. The read behavior isn't defined by the protocol but rather the deployment configuration. 

There are at least two possible behaviors. The read operation can:
    
* Block until the local transaction is committed - this will happen when local transaction operates in `Serializable` isolation level. This is the default configuration for Microsoft Distributed Transaction Coordinator[^2], and Microsoft SQL Server, but can be changed on a per-transaction basis,
* Return the last committed value (different from the one written by the local transaction) - this will happen when local transaction operates with `Snapshot` isolation.

In summary, 2PC does not provide atomic visibility of writes in a system when there are transactions committed with 2PC and other local transactions running at the level of each participant. The exact behavior isn't defined by 2PC but depends on the concrete implementation of the protocol, resources involved, as well as deployment and runtime configuration.

### 2PC can be high available
Any non-trivial protocol defines failure conditions that it's able to tolerate and 2PC is no exception. What is specific to 2PC is that some types of failures can make participants get "stuck". Whenever a participant votes "YES" it's unable to make any progress until hearing back from the coordinator. 

What might be the reasons for a participant getting stuck? First, the failure of the coordinator. Secondly, network partitioning between the coordinator and the participant[^3]. The likelihood of getting stuck is conditioned by the coordinator's availability and the probability of network failure. By making the failures less likely we can make 2PC more available.

{{< figure src="/posts/2pc-no-progress.jpg" title="Participant in the 'stuck' state">}}

This touches on the implementation and configuration aspect already mentioned. For example in the MSDTC, the coordinator is a single process but can be deployed in a fail-over cluster mode. That is a deployment decision. There is also nothing in 2PC that prevents the coordinator from being implemented as a quorum of processes[^4]. 

Finally, if all the parties (the coordinator and all the participants) are running in the same local network, on a single cluster or inside a single VM, then what is the probability of network partitioning? 

As always, context is king.   

### Commit latency is not the biggest problem
Committing in 2PC requires 2 round trips between the coordinator and each participant, and there are `4n` messages generated, where `n` is the number of participants. This is sometimes viewed as the root cause of many practical problems with the protocol. It isn't ideal but only surfaces other, bigger problem.

The problem is potential contention at the participant level caused by locking, especially when dealing with relational databases. Holding locks means that other transactions dealing with a given piece of state need to wait for the transaction to commit to make any progress.

This situation exists without 2PC but the protocol makes is pretty much always worst as in 2PC the time the locks are held is defined by the slowest participant.

### 2PC fits the cloud quite well
It is well known that 2PC is used by the cloud vendors inside their services[^4] and can be used by the users when running at the level of IaaS. That said, none of the cloud vendors support MSDTC and/or XA at the level of native cloud services i.e. native service can't participate in 2PC. 

Often, availability and performance are claimed to be the reasons for that. Although these two are not the strongest points of 2PC, it can be argued that security (or lack of it) is even more important. 

2PC assumes a high degree of trust between the participants and the coordinator. One could imagine an evil user operating a specially crafted coordinator to exhausts the participants' resources by purposefully letting transactions hang in the "stuck state".

From the cloud vendor perspective that could have quite a damaging consequences. According to the protocol participant is not allowed to make any progress after voting "YES". So in case of malicious coordinator, they would have to break the protocol or allow their resources to be blocked. 

Even if the cloud vendors provided their coordinators as the only valid option, a malicious participant could still cause a lot of harm. Enabling cloud services to act as 2PC participants is effectively opening doors for a Denial of Service (DoS) attack[^5][^6]. 

### 2PC is not the only commit protocol
2PC is just one possible solution to atomic commit. It works well in certain scenarios but performs poorly when used in an environment that violates its assumptions. 

In fact, there are very few assumptions that 2PC makes about the participants. Putting more constraints around transaction determinism allows for alternative approaches that minimize the lock holding time [^7]. 

When we acknowledge the lack of atomic visibility and work with participants that guarantee commit success by their very nature (like message queues) it's possible to end up with a commit protocol that requires a single sequential write to each participant[^8].   

## Summary
Hopefully, this post puts a bit more light on 2PC and what is it that we get from the protocol. Although the era of 2PC is coming to an end, it's good to know what guarantees we need to provide by other means in the systems we build. 

[^1]: [Transaction Management in the R* Distributed Database Management System](http://www.cs.cmu.edu/~natassa/courses/15-823/F02/papers/p378-mohan.pdf) – Mohan et al. 1986
[^2]: an implementation of 2PC built into Windows
[^3]: these faults need to happen during the voting phase. There are extensions to the protocol like Cooperative Termination Protocol (CTP) that try to mitigate the "stuck state" problem but don't eliminate them in a general case.
[^4]: *"(...) Running two-phase commit over Paxos mitigates the availability problems."* in [Spanner: Google’s Globally-Distributed Database](https://static.googleusercontent.com/media/research.google.com/pl//pubs/archive/39966.pdf)
[^5]: the only case of 2PC in the cloud at the PaaS level we know of is [Elastic Transactions](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-elastic-transactions-overview#limitations) in Azure SQL DB. That said, the coordinator is part of the database instances and Azure SQL DBs are the only allowed participants.
[^6]: *"(...) Ultimately, MSDTC is a single-node/cluster and local-network technology, which also manifests in its security model that is fairly difficult to adapt to a multitenant cloud system. (...)"* by Clemens Vasters in [Distributed Transactions and Virtualization](http://vasters.com/archive/Distributed-Transactions-And-Virtualization.html)
[^7]: [It's Time to Move on from two Phase Commit](http://dbmsmusings.blogspot.com/2019/01/its-time-to-move-on-from-two-phase.html) by Daniel Abadi
[^8]: [Outbox pattern](https://docs.particular.net/nservicebus/outbox/) is a commit protocol implementation that works on two participants and assumes that writing to the message queue is idempotent and will always succeed