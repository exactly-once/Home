### Consistent messaging, why bother?

In one of the previous posts we argued that the notion of *idempotency* is not helpful when talking about messaging. We used the term *consistent messaging* that is much broader. Now you might argue (and you would be right), why do I need to care about this?

First, you only do need to care about consistent messaging if your message processing logic needs to be correct every time. Take sensor reading processing as an example. Do you need to be 100% sure that you don't take a particular reading twice when calculating the average room temperature? Probably not. There are domain which accept *some* degree of imprecision. In these cases you are better off using some best-effort solutions.

On the other hand if you are in the process of processing a purchase order, you do want to make sure that everything is correct, from the initial submission of that order to updating the monthly sales figures. But even in that case one can imagine a system where there is a single web controller that has `ProcessOrder` action. That action opens a database transaction and, in that transaction, conducts the whole order processing logic. As a result, after the transaction commits, every piece of data the company needs is in the database and in case of an unlikely failure, nothing is persisted and the user is forced to click that Submit button again.

As funny as this description might sound, people have been building systems like this for a long and they still do. Nothing wrong about it. Studies show (TODO: citation) that vast majority of microservice systems use request-response HTTP communication. This approach is ideal for systems that are focused on reading/showing information.

Some systems are write-focused, however. In these systems we learnt to break down large processes into a serious of steps, each step done by a separate component with its results persisted in a different database (TODO: link to Garcia Molina). This is exactly where you do need to start paying attention to consistent messaging.

If your business process is broken down into a series of steps, each step triggered by a message sent by the previous step, it is essential to ensure message processing is consistent, that is

"... the messaging endpoint produces observable side-effects equivalent to some execution in which each logical message gets processed exactly-once"

### Summary

To summarize, here are the question you can use to determine if consistent messaging is something you should be thinking about
- Does my system needs to be always correct? Is it look more like a money transfer processor or like a AC controller
- Is my system write heavy? Does it display cat images in a very complex way or does it process business transactions?
- Do I need to break down these business transaction to separate steps or is it good enough to code the business logic in the web controller?

If you answer `yes` to all these questions, consistent messaging is something you definitely should care about. If you answer `no` that's fine. It does not mean your system is worse in any sense, just different. You probably have challenges in other areas. You might still pay attention to consistent messaging. Who knows what your next project will be?
