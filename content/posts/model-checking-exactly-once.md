---
layout: post
title: Model checking exactly-once 
date: 2020-06-18
author: Tomek Masternak, Szymon Pobiega
draft: false
---

Designing distributed algorithms is a challenging task. It's not that hard to reason about "happy paths" and show that at least sometimes the algorithm does what we intended. Checking that it **always** behaves as expected is a completely different story. 

By definition, any non-trivial distributed system is concurrent and fails partially. Both elements adding up to the combinatorial explosion of possible executions - too many to fit in a single person's head or analyze by hand. Fortunately, there are well-established verification methods we can use to do more rigorous testing.   

### Welcome to TLA+

If there's one person to know in Distributed Systems research it's [Mr. Leslie Lamport](https://en.wikipedia.org/wiki/Leslie_Lamport). He's a father to many discoveries and inventions in this area, including formal verification techniques. Since 1999 he's been working on TLA+ - a specification language, and TLC - a checker for validating claims about models expressed in the language[^1].

In this post, we are not going to introduce you to TLA+ but rather provide some intuition and context needed to understand how we used it to validate exactly-once algorithms. If you are new to the subject we encourage you to have a closer look. There are several resources available on-line[^2] that do an awesome job at teaching TLA+.

### Modelling systems with TLA+

TLA+ is a specification language for describing digital systems. A model of a system expressed in TLA+ consists of two elements: an initial state, and a next-state relation. The relation links a state to a set of possible next states. The fact that there might be several possible next states enables expressing nondeterministic behaviors caused by concurrent processing and partial failures. 

Applying the next-state relation on the initial and the following states generates all possible system executions - sequences of state transitions the system can take. Such a model is a directed graph where nodes are states and there is an edge from state A to state B if B belongs to the next states set of A. Any possible execution of the system is some path in that graph. Validating the model is checking that some properties are true for all the paths.               

{{< figure src="/posts/model-checking-state-space-example.png" title="CAN bus protocol model visualization." attr="https://www3.hhu.de/stups/prob/index.php/File:CANBus_sfdp.png">}}

The first step in using TLA+ is to create a model of the system. By definition, a model is a simplification, in our concrete case, a reduction necessary to make the verification feasible. We need to express only the essential parts of our system, otherwise, the state space size (number of unique system states) will be too big for the checker to handle. As with any modeling activity figuring out what are the important parts is the tricky bit. 

We already touched on the subject in the introduction saying that distributed systems are mainly about concurrency and partial failures. Our goal is to verify that the system behaves as expected in the face of this reality. As a result, nondeterminism caused by concurrency and possible failures are the key elements that should make it to the model.

Finally, a note of caution. To create a useful model one needs a thorough understanding of the system. It requires a good understanding of the communication middleware, storage systems, libraries, etc. to properly express their concurrency and failure characteristics. It might be tempting to start with the model but based on our experience we wouldn't recommend this route[^3].

### Modelling exactly-once

We are not going to look at the specification line-by-line - we encourage all the readers to have a look at the [srouce code](https://github.com/exactly-once/model-checking/blob/master/exactly_once_none_atomic.tla) for the complete picture. We used PlusCal to create the model - a Pascal-like language that gets transpiled to TLA+ by the toolbox. We think PlusCal makes it easier to understand the logic of the algorithm - especially for the newcomers.

[The specification](https://github.com/exactly-once/model-checking/blob/master/exactly_once_none_atomic.tla) models a system with the following attributes:

* Business datastore supports optimistic concurrency control on writes
* There are no atomic writes between outbox storage and business datastore
* Message is picked from the queue and processed concurrently by the handlers
* Logical messages are duplicated 

The main goal of the specification is to enable model checking that the system behaves in an exactly-once way.

#### Scafolding

We will start with the scaffold for the specification, modeling input and output queues, business data storage, and message handlers.  

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

The model describes the state using a set of variables (lines 13-18). Input and output queues are modeled with sets (no ordering) with each message having a unique `id` and `dupId` unique for each duplicate. The business data storage (line 14) is a record that holds a sequence of snapshots (all versions of the state including the newest), `ver` field used to model optimistic concurrency on writes, and `tx` field needed by the algorithm to commit message processing transactions. Finally, there are two variables modeling the outbox store. 

The system starts with all an empty state except the input queue which contains `MessageCount*DupCount` messages. There are two handlers (this is controlled by the `Processes` sequence) that operate in a loop (line 27) processing one message at a time.  

The specification already expresses some non-determinisms as there is no coordination between the handlers. E.g. an execution in which the first handler processes all the messages as well as one in which it processes none of the messages both belong to the model.   

#### Termination

Before checking any other poperties it's good to make sure that the system doesn't get stuck in any of the executions. In our case, proper termination means that there are no more messages in the input queue and both handler are waiting in `LockInMsg`. This can be expressed in TLA+ with:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
Termination == <>(/\ \A self \in Processes: pc[self] = "LockInMsg"
                  /\ IsEmpty(inputQueue))
{{< / highlight >}}

The property states that eventually (`<>` operator) any execution leads to a state in which the `inputQueue` is empty and all processes are in `LockInMsg` label.

#### Message processing

Now let's look at message processing logic:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
if outbox[msg.id] = NULL then
   txId := (msg.id-1)*DupCount + msg.dupId;
   state.tx := txId ||
   state.history := <<[msgId |-> msg.id, ver |-> state.ver + 1]>> \o state.history ||
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

First, we check if the `outbox` contains a record for the current message. If there is not track of the message we generate a unique `txId` for this concrete execution (line 2) and run the business logic. The business logic execution is modeled by capturing `msgId` and `state.ver` in snapshot history. Please note that these operations are modeling in-memory hander state changes - `state` is a variable defined locally. 

Next, we stage the outbox records, commit the state, and apply the side effects. All this modelled as 4 separate steps using `StageOutbox`, `StateCommit`, `OutboxCommit`, and `CleanupState` labels. Separate steps model concurrency but more interestingly, together with failures model the lack of atomic writes between outbox and business data stores.    

#### Failures

Failures are the crux of the model and there are many that can happen in the system. We already made sure that the model expresses the atomicity guarantees of the storage engines. Now we need to make sure that write failures are properly represented. This has been done inside dedicated macros - one for each storage operation. Let's look into one of them:

{{< highlight prolog "linenos=inline,hl_lines=,linenostart=1" >}}
macro CommitState(state) begin
    if store.ver + 1 = state.ver then
        either
            store := state;
        or
            Fail();
        end either;
    else
        Fail();
    end if;
end macro;
{{< / highlight >}}

As we can see we start with modeling the concurrency control check on the business store. What is more interesting though, we use `either-or` construct to specify that a write operation can either succeed or fail (for whatever reason). This causes a model checker to create a "fork" in the execution history. One following the happy path and the other representing write failure. The `Fail` macro brings the handler back to the beginning of the loop - as if an exception has been thrown and caught at the topmost level.

The other classes of failures are these which happen at the boundary between queues and the handlers. There are quite a few bad things that can happen in there:
* The message lease can expire and the message can be processed concurrently - either by a different thread or different process
* There can be communication failure between the queue and the handler resulting in the message being processed more than once 
* There can be duplicates of a logical message generated on the sending end
* Handler can fail before ack'ing the message that will cause message reprocessing
* Message processing can fail multiple times resulting in message moving to the poison queue

Fortunately, from the handler perspective, all the above can be modeled with a single failure mode ie. logical message being received more than once. This has been modeled with the `dupId` field on the input message that we already talked about.

#### Checking safety

With all the pieces in place, we are ready to talk about the safety properties we want to check. This is how we defined exactly-once property in [the consistent messaging post](/posts/consistent-messaging/):

> (...) we want an endpoint to produce observable side-effects equivalent to some execution in which each logical message gets processed exactly-once. Equivalent meaning that it’s indistinguishable from the perspective of any other endpoint. 

Similarily to termination we can express that as TLA+ property:

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

This time the property is a bit more complicated - it consists of three parts that all need to be true (`/\` is a notation for logical `and`)

* `AtMostOneStateChange` states that for any message `id` in the input queue there can be at most one state change committed associated with that messages
* `AtMostOneOutputMsg` states that there can at most one output message for any unique input messages
* `ConsistentStateAndOutput` states that for any fully processed input message (a message that ended-up in the `processed` set) the output message has been generated based on the business state version that got committed 

### Summary

We hope that you gained some intuition about model checking and how valuable this technique can be. That said, it's worth stressing some points:

* You need to have in-depth knowledge about the technology to build a useful model. Otherwise, you are very likely to miss some key attributes of the system.
* Model checking doesn't prove anything. First, it's not proof in the mathematical sense, secondly, it's always a simplification, not the system itself. 
* Model sizes ie. numbers of states, used in practice are small. In our case, this was 2 handlers and 6 messages in the input queue. That said are is some empirical evidence that even small are good enough to find bugs.    
* Model checking is yet another *testing* technique - arguably quite useful in the context of Distributed Systems  

There are other bits of the specification that we did not discuss here. E.g. what are the non-trivial details needed to make the algorithm safe, how to make the model finite ... and many more. 

If there is any specific part that interests you, don't hesitate and reach out on Twitter!

[^1]: There's more that comes with the toolkit eg. IDE and TLAPS - a theorem prover developed by Microsoft Research and INRIA Joint Centre 
[^2]: [TLA+ Video Course](https://lamport.azurewebsites.net/video/videos.html) and [Specifying Systems](https://lamport.azurewebsites.net/tla/book.html) by Leslie Lamport. [Learn TLA+ tutorial](https://learntla.com/) and [Practical TLA+](https://www.hillelwayne.com/post/practical-tla/) by [Hillel Wayne](https://www.hillelwayne.com/). [Murat Demirbas](http://muratbuffalo.blogspot.com/search/label/tla) and [Marc Brooker](https://brooker.co.za/blog/) also have some great content on the subject.
[^3]: Please note that we are talking about validating production systems rather than distributed algorithms.  
