---
layout: post
title: Outbox
date: 2020-06-18
author: Tomek Masternak, Szymon Pobiega
draft: false
---

Designing distributed algorithms is a challenging task. It's not that hard to reason about "happy paths" and show (or convice oneself) that at least sometimes the algorithm does what we intended. No the other hand, checking that it **always** behaves as expected is a complatelly different story. 

All non-trivial distribured systems are concurrent by definition and fail partially. Both adding up to combinatorial explosion of number of possible executions - too many to [fit in once head](link-to-fits-in-my-head-principle) or analyze by hand.

Fortunatelly, there are well established [verification techniques](link) we can use to do a more thorough verification of any distributed algorithm.   

### Welcome to TLA+

If there's one person to know in Distributed Systems research it's probably Mr [Leaslie Lamport](). He's a father to many discoveries and inventions in this area including formal verficiation. Since 1990s (-verify date) he's been developing TLA+ - a specification language, model checker, and theorem proofer designed to help expressing and validating claims about distributed algorithms.

In this post, we are not going to introduce you to TLA+ but rather provide some intuition and context needed to understand how we used it to validate outbox algorithms. If you are new to the subject we encourage to have a deeper look. There are [several](links) resources available on-line that do an awesome job at intoducting TLA+ and how to use it.

### Modelling systems with TLA+

TLA+ is a specification language for describing digital systems. A [model of any system](link-to-system-model) expressed in TLA+ consists of a initial state and a transition function. The function takes a state as an input and returns a set of possible next states. The fact that there might be number of possible next states enables expressing nondeterministic behaviors. 

The inital state and the transition function are enough to express all system behaviors - sequences of possible states transitions. A model is a directed graph were nodes are states and there is an edge from state A to state B if B belongs to the next states set of A. Finnaly, any concrete execution of the system is some path in that graph.              

{{< figure src="/posts/model-checking-state-space-example.png" title="CAN bus protocol implementation visualized as directed graph of states." attr="https://www3.hhu.de/stups/prob/index.php/File:CANBus_sfdp.png">}}

Model checking is an approach in which the verification gets performed on a model of the system. In other words, it's not the system that is verified but it's model. TLA+ is a specification language designed to create models of distributed systems that can later be verified using TLC - a model checker provided with the toolkit. 

Model is a simplification, a reduction necassary to make the verification possible. Most aspects of the system need to be removed and only a small, essential subset gets expressed. It's not obvious what makes a given part essential. That said, looking at the claims we want to verify can shed some light on the matter.

There are two esential types of claims we want 










Be sure our intiution is correct, 
Don't start with the model - you need to know your system quite deply to create a useful abstraction
Check safety and liveness separatelly
Who developed TLA+
Other TLA+ resources
5 min intro to TLA+ 
How to express conditions we need (link to definition of exaclty-once from previous posts)
How big was the model
Example of a bug in TLA+ specification and analysis the trace
Is this a proof - no, there are other things we might have missed, but it's a pretty solid baseline
