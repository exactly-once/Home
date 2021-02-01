---
layout: post
title: FLP Inside Out
date: 2021-01-26
author: Tomek Masternak, Szymon Pobiega
draft: false
---

In 50 BC an army of Scipio allied by Juba I king of Numidia, surrounded Cezars troops stationing near Thapsus in northern Africa. Their plan was to attack the usurpator in a coordinated fashion so that he could not hold off the two armies combined. Cezar made the first move though and didn't give his opponents a chance to put the plan into action.[^1] 

If only Scipio and Juba had a chance to read the FLP paper would they realize the plan could not work at all! 

## Understanding FLP

The tongue in cheek introduction to this post tries to make the point that FLP is easy to get wrong (and to our experience has been) both at the level of the proof as well as in terms of practical consequences. This post adds some commentary on both topics which can hopefully make the understanding of the result a bit more intuitive.

## The proof

TODO: not showing everyting but only part that are missing from the paper and a great write-up on paper-trail.

### Model strength

TODO: model strenght - the model is very strong i.e. I/O Automata can represent programs that are impossible e.g. they solve the Halting problem [ref to the yale ds notes]. Next the netowrking model is super strong in fact atomic bradcast assumption means that at the newtork layer the consensus is solved (the author could not know about that though as the reduction was to proved at the publication time). 

### Lemma 1

> Suppose that from some configuration C, the schedules sigma1 and sigma2 lead to configurations C1 and C2, respectively. If the sets of processes taking steps in sigma1 and sigma2, respectively, are disjoint, then sigma2 can applied to C1 and sigma1 can be applied to C2, and both lead to the same configuration C3.

This part might be a bit confusiong unless we understand what is the set of processes taking steps in a schedule. Step made by process `p` is defined as a `receive(p, m)` (followed by internal state change and number of `send` operations). So the set of processes taking step in a schedule is a set of all processes `p` that make at least one receive operation in that schedule. It's important to realize that a single step defines not only a process that receives a message but also an exact message that gets received by that process. 

With that in mind Lemma 1 becomes quite intuitive. An internal state of a process and messages that it has sent in a given schedule is fully determined by set of messages it received and order of that receival. If a schedule does not contain process `p` it cannot affect `p` in any way (either by chaning the message set or changing set of messages received).

### Lemma 2

#### Chain of initial configurations

> Any two inital configurations are joint by a chain of initial configurations, each adjacent to the next. Heance, there must exists a 0-valent initial configuration C0 adjacent to a 1-valent initial configuration C1.

This might not be obvious at the first sight. Lets start by look at the set of all inital configurations for 3 processes. An initial configuration is fully specified by values of 3 `x` registers each storing either `0` or `1`. There are 2^3 initial configurations that we can represent as 3-digit binary number. A chain of initial configurations in which one differs by a single bit is simply a enumarion of [Gray coding](TODO: add ref) for 3-digit binary number. In our case, `000` -> `001` -> `011` -> `010` -> `110` -> `101` -> `100`.

If the chain contains both 1-valent and 0-valent intial configuration it's trivial to see that we can travers the sequence from one to the other and must arrive at an edge that connects 1-valent and 0-valent configurations that differ by a single bit i.e. by a single `x` register.

//TODO: include a tesseract of 

#### Internal state of the processes are not important

But what about internal state of the process? Why isn't it mentioned in anywhere in the lemma? Does this imply that each process must start with the same internal state? Can we "break" the proof by coming up with an alogrithm that starts off with processes having different internal state? 

The answer is ... we don't care if all processes have the same internal state or not. If an alogrithm is deterministic it has to define the internal state of each process before any of the values for `x` registers get defined. Futhermore, the state can depend only on some knowledge available before the algorithm starts e.g. process identifier. What this means is that even if each process has different internal state, these (different) states will be same for each possible permutation of the `x` register values if the algorithm is deterministic. 


### Lemma 3

#### C0 and C1 that are one step apart

> (...) D contains both 0-valent and 1-valent configurations.
> Call two configurations neighbors if one results from the other in a single step. By an easy induction, there exist neighbors Co, Ci E, such that Di = e(Ci) is i-valent, i = 0, 1.

Why is it true that there have to be C0 and C1 that are only one step aparts? Well if C is the configuration we start from than all reachable configurations through schedules without `e` form a DAG. Nodes are configurations of the system and edges connect configurations if there is an event that can lead from configuraiton to the other. D as defined in the paper can be "visialized" as a layer of nodes atop the DAG (reachable via `e` event). We already know that D contains both 0-valent and 1-valent configuration (let's call them D0' and D1'). Let's consider a path between C0' and C1' nodes that connect to D0' and D1' via `e`. There must be an edge `e'` on that path that connects nodes with neighroubs in D that have different valence.

//TODO: a layered DAG visualization

### Proof

#### Message ordering inside Message Buffer

> Suppose then that configuration C is bivalent and that process p heads the priority queue. Let m be the earliest message to p in C’s message buffer, if any, and 0 otherwise.

The final proof depends on ordering inside Message Buffer. It is assumed that Message Buffer orders messages based on the send time. Why is that important, would it be possible to skip that part and e.g. prove that for any bi-variant configuration C there is some schedule sigma such that sigma(C) is bi-variant? 

The answer is .. no. The ordering in Message Buffer and the fact that each in each round we take the oldest message for a given process enusers that each message is eventually delivered. If we can't show that each message is eventually delivered we can't be sure that a given schedule is admissable.


## Practical consequences



[^1]: The story is pure facts and has been described in [Asterix the Legionary](https://www.asterix.com/en/the-collection/albums/asterix-the-legionary/) which we highly recommend reading. 
