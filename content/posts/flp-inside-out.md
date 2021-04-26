---
layout: post
title: FLP - a few technical notes
date: 2021-03-02
author: Tomek Masternak, Szymon Pobiega
draft: false
---

In 50 BC an army of Scipio allied by Juba I king of Numidia surrounded Cezar's troops stationing near Thapsus in northern Africa. They planned to attack the usurper in a coordinated fashion knowing that he could not hold off the two armies combined. Cezar made the first move though and didn't give his opponents a chance to put the plan into action.[^1] 

If only Scipio and Juba had a chance to read the FLP paper would they realize the plan could not work at all! 

## Understanding FLP

The tongue in cheek introduction to this post tries to make the point that FLP is easy to get wrong (and to our experience has been) both at the level of the proof as well as in terms of practical consequences. This post adds some commentary on both topics which can hopefully make the understanding of the result a bit more intuitive.

## The proof

We are not going to discuss the whole proof. There is a great [post](https://www.the-paper-trail.org/post/2008-08-13-a-brief-tour-of-flp-impossibility/) by [Henry Robinson](https://twitter.com/HenryR) so have a look at it first if you haven't already[^1]. We will focus on the parts that are briefly mentioned by the [original paper](https://groups.csail.mit.edu/tds/papers/Lynch/jacm85.pdf) or left out as an exercise for the readers.

### The initial state of the process does not matter

> Initial states prescribe fixed starting values for all but the input register; in particular, the output register starts with value b.

This quote comes from section 2 of the paper (Consensus Protocol) that proceeds the proof. It sounds like a strong assumption and might trigger some questions. How strong of an assumption is this? Is consensus solvable in FLP's model if we remove this requriement on the initial state? How important is this assumption really?

First, the assumption is used as a constraint on the information available to the processes. It ensures the protocol does not initialize process states using information derived from the environment (e.g. clock values) or some global information shared between the processes.

Secondly, it is makes the proof a bit easier as for any given protocol the initial configuration of the system is fully specified by the input registers (their number and values). At the same time it does't prevent a given protocol to have an "initialization phase" performed on the first `receive` operation.

### Lemma 1

> Suppose that from some configuration `C`, the schedules `sigma1` and `sigma2` lead to configurations `C1` and `C2`, respectively. If the sets of processes taking steps in `sigma1` and `sigma2`, respectively, are disjoint, then `sigma2` can be applied to `C1` and `sigma1` can be applied to `C2`, and both lead to the same configuration `C3`.

Fist, let's remind ourselves what is the set of processes that take steps in a schedule. A step made by process `p` is defined as a `receive(p, m)` followed by internal state change and some follow-up `send` operations. From a single process perspective, if a schedule does not contain process `p` it doesn't affect `p`'s internal state, so it can be executed before, after or be interleaved with any schedule in which `p` takes steps. So, for any `C1` and `C2` for which the sets or processes taking steps are disjoint any interleaving of `C1` and `C2` (including concat(`C1`,`C2`) and concat(`C2`,`C1`)) will lead to a configuration with all processes having the same state. 

The second part of the system configuration is the content of the message buffer. A message can be removed from the buffer by executin `sigma` only if the set of processes taking steps in `sigma` contains the process the message is destined to. This means that `C1` and `C2` will remove a disjoint set of messages from existing in `C`. Secondly, messages are added to the buffer only by processes that first receive a message and the content of the message added is fully determined by the state of that process and the message received. This in turn means that for any interleaving of `C1` and `C2` the set of messages added to the buffer will be the same.   

### Lemma 2

#### Chain of initial configurations

> Any two initial configurations are joint by a chain of initial configurations, each adjacent to the next. Hence, there must exist a 0-valent initial configuration `C0` adjacent to a 1-valent initial configuration `C1`.

Let's look at an example with 3 processes. Any initial configuration can be encoded as a 3-digit binary number (each digit representing the value of one of the input registers). The chain the author's are talking about is simply an enumeration of the [Gray coding](https://en.wikipedia.org/wiki/Gray_code) for 3-digit binary number i.e. `000` -> `001` -> `011` -> `010` -> `110` -> `101` -> `100` (each item in the sequence differs on a single bit from it's predecessor). Such a sequence exists for any number of processes.

Finally, if the chain contains both 1-valent and 0-valent configurations it's trivial to see that somewhere on the path between one and the other there must be an edge connecting 1-valent and 0-valent configurations.

### Lemma 3

#### C0 and C1 that are one step apart

> (...) D contains both 0-valent and 1-valent configurations.
> Call two configurations neighbors if one results from the other in a single step. By an easy induction, there exist neighbors `C0`, `C1` \in `E`, such that `Di` = `e(Ci)` is i-valent, i = 0, 1.

Why is it true that there have to be `C0` and `C1` that are only one step aparts? Well if `C` is the configuration we start from than all reachable configurations through schedules without `e` form a directed graph. Nodes are configurations of the system and edges connect configurations if there is an event that can lead from configuraiton to the other. `D` as defined in the paper can be "visialized" as a layer of nodes atop the graph (reachable via `e` event). We already know that `D` contains both 0-valent and 1-valent configuration and not bi-valent configuration (this is the assumption for the proof by contradiction).
Let us choose a 1-valent configuraiton `D1'` and 0-valent configuration `D0'`. We know that there must be a path from `C` to `C1'` and `C0'` such that `Di'` = `e(Ci')`. Now `e(C)` is either 0 or 1 valent, so we are sure there is a path that connects two configurations leading to 0 and 1 valent configuration in `D`. Now we can use the "chain" approach we already know to show that there is some edge on that path which connects two configurations we are looking for.


### Proof

#### Message ordering inside Message Buffer

> Suppose then that configuration C is bivalent and that process p heads the priority queue. Let m be the earliest message to p in C’s message buffer, if any, and 0 otherwise.

The final proof depends on ordering inside Message Buffer. It is assumed that Message Buffer orders messages based on the send time. Why is that important, would it be possible to skip that part and e.g. prove that for any bi-variant configuration C there is some schedule sigma such that sigma(C) is bi-variant? 

The answer is .. no. The ordering in Message Buffer and the fact that in each round we take the oldest message for a given process enusers that each message is eventually delivered. If we can't show that each message is eventually delivered we can't be sure that a given schedule is admissable.

## Practical consequences

### What does "solve" even mean

There are number of consensus protocols out there[^3] used every day that do a great job at making sure processes arrive at some decissions. It's not because they make use  


[^1]: The story is pure facts and has been described in [Asterix the Legionary](https://www.asterix.com/en/the-collection/albums/asterix-the-legionary/) which we highly recommend reading. 
[^2]: If you prefer video content we can recommend Papers We Love New York City [session](https://www.youtube.com/watch?v=Vmlj-67aymw). 
[^3]: 