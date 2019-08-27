# Sync-async boundary

If my experience in the IT industry has taught me anything it would be that drawing boundaries is the most important part of the design process. Boundaries are essential for understanding and communicating the design. The sync-async is an example of a boundary that is useful when designing distributed systems.

## Sync

The most popular medium for building synchronous systems is HTTP. In the outermost layer, the user's action is transformed into an HTTP request by the code running in the browser and submitted to one of the backend components for processing. The response carries the result of the action for rendering on screen. Internally the component that does the processing can delegate part of the work to other components. It does so by sending its own requests and collecting responses. These other components can do the same. This can result in the request "tree" that can span dozens of components.

## Async

In an asynchronous system components communicate by sending one-way messages to each other via message queues. The user's action is captured in a message that is put onto a queue. The message is picked up by another component. Processing a message can result in sending out more messages. Finally, the user interface component can receive a message that captures the result of the whole multi-step operation.

## Trade-offs

The synchronous approach allows a more straightforward programming model as the HTTP-based interactions can be represented as function calls returning values (or raising errors). It can be usually assumed that synchronous calls return quick and immediate responses. This allows building simple user interfaces that block until response comes back.

The main problem with the synchronous approach is the temporal coupling it introduces. In order to process the request all the components involved need to be available at the same time. If processing the initial request results in more request (which in turn generate more requests) it can quickly get out of hand. The more parties need to be available at the same time, the higher the likelihood of any one of them failing and undermining the whole process.

The asynchronous approach solves this problem by introducing queues and one-way messages. The sender or publisher puts the message onto a queue or topic and can immediately move on to processing subsequent work items. It does not waste time and resources actively waiting for a response. If the recipient is unavailable that's OK too. The queue will ensure the message is not lost and that it will be eventually delivered. 

This huge advantage of asynchronous systems becomes a disadvantage when it comes to building user interface components. The time to process a message is generally longer and more involved than in a synchronous system. In order for the user to know the state of the system, it might be necessary to visualize pending operations related to messages that have been sent but not yet processed. This introduces the need to keep the state client-side. Depending on the complexity of the problem, it can lead to a fully-fledged multi-master replication as multiple clients can send messages that compete to modify the same set of data.

## The middle ground

Whenever there are two extreme approaches, each with their strong and weak points, someone has to make a decision to pick one or the other. But what if such a decision did not have to be made for the entire system? Here's where the sync-async boundary becomes useful.

The synchronous approach shines when used close to the user and for work that is highly interactive, like adding or removing items from a shopping cart. It begins to cause problems when used to implement complex logic or long-running non-interactive processes. Fortunately this is precisely where the asynchronous approach works best. 

## The pattern

Divide the system in two parts. The synchronous part includes components running in the browser and ones that process HTTP requests sent by the browser. The asynchronous part contains all the components which do not interact with the user. Let's call the former *edge* and the latter *interior*.

The user interacts with the *edge* of the system by working on a private set of data in a synchronous manner. Once that data set is ready, it can be submitted for processing. This is when, at the boundary, the submit HTTP request is transformed into a message that captures the user-created data and notifies the components in the *interior* of the system.

## Exactly once

As we stated before times, a successful exactly-once processing strategy depends on the ability to assign unique message ID in a deterministic manner. In the sync-async boundary approach the message ID is generated at the boundary based on the identity of the private data set. This guarantees that potential duplicates carry the same ID and therefore can be identified at their destination endpoints. 

## The story continues

The sync-async boundary pattern is invaluable in designing distributed software systems as it allows combining different strengths of both sync and async approaches while minimizing their weak sides. It is useful in one more way. It provides a very useful...

TODO
