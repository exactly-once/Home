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

We are not going to look at the specification line-by-line - the source code is [available](https://github.com/exactly-once/model-checking/blob/master/exactly_once_none_atomic.tla) on GitHub and we encourage all the readers to have a look. Secondly, we are not going to use TLA+ directly but PlusCal instead. PlusCal get's transpiled to TLA+ and among others traits, has a syntax similar to many main-stream languages making it easer to understand - especially for the newcomers.

The specification models a generic system with the following assumptions:

* Business data store supports optimistic concurrency control
* There are no transactions between outbox storage and business data store
* Message can be concurrently processed by multiple handlers
* Messages are duplicated 

We will start with the scafold for the specification ie. modelling input and output queues, business data storage, and message handlers.  

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
CONSTANTS MessageCount, DupCount, NULL

IsEmpty(T) == Cardinality(T) = 0

Processes == 1..2
MessageIds == 1..MessageCount
DupIds == 1..DupCount
VersionIds == 0..2*MessageCount
TxIdx == 1..MessageCount*DupCount

(*--algorithm exactly-once
variables
    inputQueue = [id : MessageIds, dupId : DupIds],
    store = [history |-> <<>>, ver |-> 0, tx |-> NULL], 
    outbox = [r \in MessageIds |-> NULL],
    outboxStagging = [t \in TxIdx |-> NULL],
    output = { },
    processed = { }
(...)
fair process HandlerThread \in Processes
variables
    txId,
    msg,
    state, 
    nextState
begin
MainLoop:
    while TRUE do
    LockInMsg:
        await ~ IsEmpty(inputQueue);
        (...)
    end while;
end process;
end algorithm; *)
{{< / highlight >}}

The model describes the state using set of variables (lines 13-18). Input and output queues are represented as set of records with unique `id`. The business data storage (line 14) consists of a sequence of snapshots and contains `ver` field used to model optimistic concurrency control on writes. Finally, there are two variables modelling the outbox store.

The system starts with all storages empty except the input queue which contains `MessageCount*DupCount` messages. Every handler operates in a loop (line 27) processing one message at a time.  

As we can see the model already expresses some non-trivial non-determinisms resulting from number of processes and execution steps defined. The specification doesn't define any rules about how the messages are to be processed. E.g. an execution in which the first handler processes all the messages as well as one in which it processes none of the messages both belong to the model.   

#### Termination

To check termination ie. making sure that the system always drains the input queue, the following property has been defined:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
Termination == <>(/\ \A self \in Processes: pc[self] = "LockInMsg"
                  /\ IsEmpty(inputQueue))
{{< / highlight >}}

As already mentioned we can use model checking to verify that the property is true for all executions of the system. The definition states that eventually (`<>` operator) any execution leads to a state in which the `inputQueue` is empty and all processes are in `LockInMsg` label.

#### Message processing

Now let's look at message processing logic:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
if outbox[msg.id] = NULL then
   txId := (msg.id-1)*DupCount + msg.dupId;
   state.history := <<[msgId |-> msg.id, ver |-> state.ver + 1]>> 
                     \o 
                     state.history ||
   state.tx := txId ||
   state.ver := state.ver + 1;
StageOutbox:
   outboxStagging[txId] := [msgId |-> msg.id, ver |-> state.ver];
StateCommit:
   CommitState(state);
    
OutboxCommit:
   CommitOutbox(txId);
StateCleanup:
   CleanupState(state);
end if;
{{< / highlight >}}

First, we check if the `outbox` contains a record for the input message. If not we generate an id unique to this processing and execute the business logic (update history log of the state and bump the expected version number). Next, we stage the outbox records and commit the state. 

At this point the message processing is committed. The side effects won't be fully visible until we exectue `CommitOutbox` and `CleanupState`. 

#### Failures

Let's look into one of the `CommitState` macro:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
macro CommitState(state) begin
    if store.ver + 1 = state.ver then
        either
            store := state;
        or
            Rollback();
        end either;
    else
        Rollback();
    end if;
end macro;
{{< / highlight >}}

As we can see it does the concurrency control check on the busniess store. What is more interesting is models process failures as well. When the version number maches the state is either committed (line 4) or we fail (line 6). The `either-or` statement expresses that at this stage in either one of these is possible.

#### Checking safety

Now that we went through state, concurrency and failures modelling let's see what is the safety property that we defined:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
AtMostOneStateChange ==
 \A id \in MessageIds : 
    Cardinality(WithId(Range(store.history),id)) <= 1
    
AtMostOneOutputMsg ==
 \A id \in MessageIds : 
    Cardinality(WithId(output, id)) <= 1

ConsistentStateAndOutput ==
 LET InState(id)  == 
        CHOOSE x \in WithId(Range(store.history), id) : TRUE
     InOutput(id) == 
        CHOOSE x \in WithId(output, id) : TRUE
 IN \A m \in processed: 
     InState(m.id).ver = InOutput(m.id).ver
    
Safety == /\ AtMostOneStateChange 
          /\ AtMostOneOutputMsg 
          /\ ConsistentStateAndOutput
{{< / highlight >}}

It consists of three parts. `AtMostOneStateChange` states that for any unique message id in the input queue there can be only one state change committed associated with that messages. Similarlity, `AtMostOneOutputMsg` states that there can be only one output message for any unique input messages. Finally, `ConsistentStateAndOutput` makes sure that for any message that got fully processed the output message has been generated for the business state version that got committed. 

### Summary

There are many non-trivial bits of the specification that we did not discuss here. E.g. what are exact failure scenarios considered, why having message duplicates is enough to model processing retires, what was the size of the model used for model checking, what are the non-trivial details needed to make the algorithm safe ... and many more. 

If there is any specific part that intrests you, don't hesitate and reach out on Twitter!

[^1]: There's more that comes with the toolkit eg. IDE and TLAPS - a theorem prover developed by Microsoft Research and INRIA Joint Centre 
[^2]: [TLA+ Video Course](https://lamport.azurewebsites.net/video/videos.html) and [Specifying Systems](https://lamport.azurewebsites.net/tla/book.html) by Leaslie Lamport. [Learn TLA+ tutorial](https://learntla.com/) and [Practical TLA+](https://www.hillelwayne.com/post/practical-tla/) by [Hillel Wayne](https://www.hillelwayne.com/). TODO: add Murat Demirbas and Marc Brooker links
[^3]: Please note that we are talking about validating production systems rather than distributed algorithms.  