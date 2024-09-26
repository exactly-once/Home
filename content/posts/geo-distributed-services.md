# Geographically distributed services

Previously in the series (LINK to event-vs-command) we mentioned that a system may utilize two different approaches to *exactly-once message processing* based on the type of the message being sent. Later (LINK) we discussed that in some systems the different approaches to *exactly-once message processing* may be associated not with types of messages but rather internal structure of the system. Each group of services may use its own way.

This time we would like to discuss yet anther reason for using different approaches to *exactly-once message processing* within one system, namely geo-distribution of the system's components.

## Boundaries

Sometimes it is assumed that the service boundary should not cross the physical site boundary i.e. that, although the system as a whole can be geographically distributed, each service runs in one and only one site. It seems a valid approach on the surface but if you look closer, you can find a major drawback.

The purpose of dividing a system into multiple top-level components (services) is to lower the complexity of the solution. That *divide-and-conquer* strategy only works if the service boundaries are driven by natural coupling of the business domain i.e. if code that implements closely related business concepts ends up in a single service. 

If service boundaries are to be defined both by physical distribution and logical coupling, one has to give up. Either we need to learn to live with a suboptimal decomposition of the system or we need to accept that some services are indeed geographically distributed themselves.

## Geographically distributed services

Let's assume that compromising service boundaries is not an option. We are now in a situation in which internal communication within a single service can either happen inside a single site or across sites, depending on a given message type. What are the consequences of this to our *exactly-once processing* strategy? We cannot use any *atomic store-send-and-consume* technology any mode as these don't work well in a distributed environment. What are the alternatives? One is to use *atomic store-and-send* in all components of the system. The other is to use a composite approach in which a different message broker and different *exactly-once processing* approach is used within a site and outside it.

## Composite

