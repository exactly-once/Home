---
layout: post
title: Model checking exaclty-once 
date: 2020-06-18
author: Tomek Masternak, Szymon Pobiega
draft: false
---

Designing distributed algorithms is a challenging task. It's not that hard to reason about "happy paths" and show that at least sometimes the algorithm does what we intended. Checking that it **always** behaves as expected is a completely different story. 

By definition, any non-trivial distributed system is concurrent and fails partially. Both elements adding up to the combinatorial explosion of possible executions - too many to fit in a single person's head or analyze by hand. Fortunately, there are well-established verification methods we can use to do more rigorous testing.   

### Welcome to TLA+

If there's one person to know in Distributed Systems research it's [Mr. Leaslie Lamport](https://en.wikipedia.org/wiki/Leslie_Lamport). He's a father to many discoveries and inventions in this area, including formal verification techniques. Since 1999 he's been working on TLA+ - a specification language, and TLC - a checker for validating claims about models expressed in the language[^1].

In this post, we are not going to introduce you to TLA+ but rather provide some intuition and context needed to understand how we used it to validate exactly-once algorithms. If you are new to the subject we encourage you to have a closer look. There are several resources available on-line[^2] that do an awesome job at teaching TLA+.

### Modelling systems with TLA+

TLA+ is a specification language for describing digital systems. A model of a system expressed in TLA+ consists of two elements: an initial state, and a transition function. The function takes a state as an input and returns a set of possible next states. The fact that there might be several possible next states enables expressing nondeterministic behaviors. 

Applying the transition function on the initial and the following states generates all possible system executions - sequences of state transitions the system can take. Such a model is a directed graph where nodes are states and there is an edge from state A to state B if B belongs to the next states set of A. Any possible execution of the system is some path in that graph. Validating the model is checking that some properties are true for all paths in the graph.               

{{< figure src="/posts/model-checking-state-space-example.png" title="CAN bus protocol model visualization." attr="https://www3.hhu.de/stups/prob/index.php/File:CANBus_sfdp.png">}}

The first step in using TLA+ is to create a model of the system. By definition a model is a simplification, in our concrete case, it's a reduction necessary to make the verification feasible. We need to express only the essential subset of our system, otherwise, the state space size (number of unique system states) will be too big for the checker to handle. As with any modeling activity figuring out what are the important parts is the tricky bit. 

We already touched on the subject in the introduction saying that distributed systems are mainly about concurrency and partial failures. Our goal is to verify that the system behaves as expected in the face of this reality. As a result, nondeterminism caused by the concurrency and possible partial failures are the key elements that should make it to the model.

Finally, a note of caution. To create a useful model one needs a thorough understanding of the system. It requires a good understanding of communication middleware, store systems, libraries, etc. to properly express their concurrency and failure characteristics. It might be tempting to start with the model but based on our experience we wouldn't recommend this route[^3].

### Modelling exactly-once

What is an endpoint? 
How to model concurrent receivers, message leases and processing failures? 
What are the assumptions that we make about consistency models of storage engines?
What is the formal expression of `exactly-once` property?

### Some non-trivialities

TransactionId as messageId instead of random guid









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

[^1]: There's more that comes with the toolkit eg. IDE and TLAPS - a theorem prover developed by Microsoft Research and INRIA Joint Centre 
[^2]: [TLA+ Video Course](https://lamport.azurewebsites.net/video/videos.html) and [Specifying Systems](https://lamport.azurewebsites.net/tla/book.html) by Leaslie Lamport. [Learn TLA+ tutorial](https://learntla.com/) and [Practical TLA+](https://www.hillelwayne.com/post/practical-tla/) by [Hillel Wayne](https://www.hillelwayne.com/). TODO: add Murat Demirbas and Marc Brooker links
[^3]: Please note that we are talking about validating production systems rather than distributed algorithms.  