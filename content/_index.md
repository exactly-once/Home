---
title: Overview
type: docs
---
TODO: we need to nail down the context:
 * Persistent messaging,
 * Performance?
 * Business model is the key thing here
 * Mention other approaches here e.g. event-sourcing

# Introduction

Whoever architects message-based distributed systems made of services needs to acknowledge two basic facts of reality i.e. **at-least-once message delivery** and **lack of transactions** between the messaging infrastructure and business data storage (* - this is not some universal rule but current status quo). 

This site gathers knowledge on approaches used in the industry to cope with these problems. It targets people building infrastructure and frameworks as well as software developers in general wanting to learn more on messaging systems.

## Context

We will focus here on enterprise systems built with modern cloud and on-prem technologies - systems that come with an interesting tension built-in (TODO: this doesn't read well). Systems that on one hand are critical for business operations hence require high level of reliability and correctness but at the same time generate most value in the area of business domain modeling.      

## Content

The content on this site comes from various sources i.e. blog posts, conference presentations, books, research papers and last but not least source code of production software systems. We cite the original source whenever one is know to us. We didn't come-up with most of the content here, however there are parts that are based mainly on our industrial experience.

## Authors

Szymon & Tomek