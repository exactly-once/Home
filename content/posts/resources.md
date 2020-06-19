# Resources

Today let's take a look at the application at runtime as it executes its program. As a result of executing, two things can happen. First, the application can modify values in its assigned memory space. This is by itself is not enough to achieve anything because the memory cannot be accessed from outside and is volatile. Once the process is restarted, all the information is gone. The Looking from the external perspective, the application interacts with a set of external resources. For an application to be useful, it needs to interact with external resources that can be modified persistently.

## Business logic

Imagine our application contains business logic that is triggered by messages sent from the outside. Unfortunately these messages can get duplicated along the way so the application can receive multiple copies of each messages. Fortunately, each message carries an ID so duplicates can be detected by comparing their IDs.

To do its job, the business logic interacts with external resources. In order to maintain correctness, the business logic needs to ensure that each message is processed exactly once. In other words, the results of processing duplicates should not be visible from outside of the application. Let's take a look how different types of resources influence how business logic needs to behave.

## Write-only resources

The write-only resources do not offer any way of querying their state. Why is that important? Imagine a situation when the application requested some operation and immediately crashed. Once the application is up again it has no way to check if the crash happened right before submitting the operation or right after it. In other words, it does not know what state whe system is in. An example of such a resource is an SMTP server. When the application needs to send an e-mail, it sends the message to the SMTP server. If that application restarts during that operation, it cannot ask the SMTP server if it received and forwarded a given e-mail. The only thing it can do is retry the send operation, possibly risking sending the e-mail twice and making the customer upset.

## Blob resources

Blob resources allow CRUD operations but do not allow storing any out-of-band information along the actual data. An example would be an image file stored in the Azure Blob Storage or S3 bucket. The application can modify the value but it cannot store additional information about the modification (such as the ID of the messages that triggered the modification). Because of that limitation, the application is not able to detect duplicates. This limits the type of modifications that can be done safely (without risking duplicate side effects). Creating and Deleting are safe operations because they are, by definition, idempotent. The result of deleting a thing twice is the same as deleting it once. Updates are not always idempotent e.g. appending information to a file is not while replacing the whole file is.

## Metadata-enabled blob resources

If the blob format allows adding meta information it gives the application much more power. An example is a json document representing a customer's order stored in the Blob Storage. Such a document can contain any out-of-band meta information. This ability is critical when trying to ensure exactly-once message processing as the metadata can contain a list of IDs of processed messages. When a new messages comes in, the application can load the resource and check in the metadata if that messages has already been processed. If so then it can safely ignore the message as a duplicate.

## Multi-entity transactional resources

Some resources allow for multi-entity transactions. An example is a SQL database. Such resources allow storing out-of-band information related to message processing in separate entities. This is convenient as it allows much more freedom with regards to how information about already processed messages is structured. 

## Query-before-submit resources

A more advanced version of write-only resources allows the application to ask about the state of a given operation in case of an unexpected restart. An example would be a web service that allows the client to pass a reference number of each operation. Before the client calls the web service, it generates and persists the reference number. Later, when it crashes and restarts it can use that stored value to check if a given operation has been received and processed by the web service. If not, it can re-submit the operation.

The problem with such resources is the fact that there is a race condition between the submit and the query. The query might return false because the submit message has been delayed by the network. The client thinks the operation did not make it through and re-submits. As a result, the web service receives and processes the operation twice.

## ID-based de-duplication resources

An even more advanced category of resources performs de-duplication of submitted operations based on the reference number provided by the client. An example would be a web service that, before processing an operation, ensures it has not been processed before. In the latter case it ignores the message.

## Summary

We can see how different categories of resources impact the way the application business should behave. In the past most line-of-business applications interacted mostly with relational databases. This is why most engineers feel comfortable using this category of resources. In recent years more and more applications are developed in the cloud. This changes not only the way they are hosted, but also the way they interact with external resources. To really benefit from the cloud the applications should use cloud-native services. These services are unlikely to be in the same category of resources as SQL databases. Here's a short summary of how to handle different resource types to guarantee exactly-once processing of message.

- Write-only resources cannot ever guarantee exactly-once semantics. Ensure your application receives messages through a message broker that offers best-effort de-duplication (like Amazon SQS FIFO or Azure Service Bus) to limit likelihood of duplicates reaching your application. If possible, avoid write-only resources.

- Prefer ID-based de-duplication resources to query-before-submit resources whenever possible. If not possible, use a message broker that offers best-effort de-duplication. There is really no reason why a web service would provide query-before-submit but not de-duplicate automatically.

- When working with blob resources always replace the whole value. Remember, blob resources cannot guarantee exaclty-once semantics for appending.

- ID-based de-duplication or query-before-submit resources can to be controlled through a metadata-enabled or multi-entity transactional resource in order to be able to store the reference number for the submitted operations. Alternatively, the message ID itself can be used as the reference number.

- Metadata-enabled blob and transactional resources allow exactly-once processing by storing information about processed message IDs. In order to guarantee the deterministic sending of messages that are result of business logic execution, these outgoing messages need also to be stored in the metadata-enabled or transactional resource. 

## Two-layered approach

The heuristics described in the previous section define a concentric two-layered architecture of the system that contains of multiple message-processing applications (also known as the microservices architecture ;-). The inner circle is formed by applications that interact with transactional and metadata-enabled resources such as databases. These applications exchange messages between themselves freely as they can both send and receive messages.

The outer circle is formed by all other applications. These applications, although sometimes can guarantee exactly-once processing (as ID-based de-duplication web services), cannot generate deterministic message IDs. As a result they are unable to send messages to other applications. 
