---
title: Solutions
bookShowToc: true
---
# Introduction

## System model

The system consists of state-ful services that process messages from the input queue, update their state based on the message content and their current state and publish new messages. 

[input_message, current_state] [--/generate/--> [input_msg_ack, state_change_ops, msg_send_ops] --/application/-->] [new_state, output_messages]

TODO: we need diagram

In this context a message processing consists of two phases. First, calculating side-effects and later applying them on internal state and messaging infrastructure.


## Idempotency
 * We present different solutions in pattern (context, tradeoffs) approach
 * Refs: https://queue.acm.org/detail.cfm?id=2187821

An operation is called idempotent if executing it once has the same effect as executing it multiple times. Let's assume that we can make all operations in a system idempotent. Would that help us cope with anomalies possible when dealing with no transactional guarantees? 

The answer is yes, we can relatively easy cope with no transac
]tional guarantees if all operation are idempotent. We already said that in message processing system an operation can be represented as [input_ack, state_delta, set_of_output_messages]. In this context idempotency means that re-processing a message results in the same new_state and output_messages, and applying them on the underlying resources has the same effects. 

If we make sure input_ack is the last side-effect applied we can re-try message processing until all parts execute successfully. Eventually, each message gets processed and all side-effects are the same as if each message was processed exactly-once. 

## User code idempotency
 * The problem is never solved,
 * Idempotency over message re-ordering is hard/impossible for non-trivial state
 
Idempotency can be designed into the business domain and ensured in the user code. What it means is that side-effects are the same no matter how much the logic implemented by the system builders gets executed. 

Though possible in theory, this is way harder than it sounds. The difficulties in practice come from two places i.e. need for determinism in the user-code logic and possible message re-ordering.


First, unbox the requirements for the side-effects to be same on each execution. It is equivalent to saying that  




 Though possible in theory, we have never seen such approach in practice. Why? For starters this approach requires work per each operation - the problem is never solved but rather solved over and over again for each operation which puts a significant burden on the maintainability of the system. 

The biggest problem however is the fact that this approach requires system remodeling - something exactly opposite to what we usually want. We don't want to sacrifice any flexibility at the business modeling level, a place were we generate the most value. (TODO: reference the ubiquitous language). 

Secondly, we could lean on a generic solution - treating the problem as a cross-cutting concern and solving it once, independently of the business logic. To figure out how could that work, and what is it, that we actually need let's have a closer look at the state of our system.

## Business level idempotency
 * This is only a theoretical solution
 * Is it idempotent over re-ordering
 * I don't want to change my domain
 * It has to be deterministic!
 * It's never solved!

## A Compromise (Bare minimum)
 * Only two resources - how to deal with more?
 * Non-overlapping state partitioning
 * Optimistic concurrency on storage
 * Single handler for a message (single message handler per queue)

## BlobStorage + AzureServiceBus
  * TODO: what happens on failures? How can we use leasing on blobs? outbox clean-up? we do need TLA+ for this
  
 * Get inputM = {m_id}
 * Find\Create state
 
 * Check [Checkpoint 1] and push to [Checkpoint 3] if needed /* we don't need to dispatch as original message will push it forward */
 * Check [Inbox] for m_id and `dispatch outbox` if needed
 
 * Calculate `state_delta` and `M` /* this is handler invocation */
 
 * Store outbox record = {`o_id`, `M`} /* this fail and it's fine :) */
 * [Checkpoint 1] Store {`state_delta`, `tx(o_id, m_id)`} /* this could fail e.g. optimisic concurrency -> we need clean-up */
 * [Checkpoint 2] Store inbox record = {`m_id`, `o_id`, done:`false`}
 * [Checkpoint 3] Remove `tx(o_id, m_id)`
  
 * `dispatch outbox`
 * (ACK:m_id)