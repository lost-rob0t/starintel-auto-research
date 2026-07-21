---
name: "authorization"
description: "Enforce default-deny Starintel dataset, document, search, ingest, and actor authorization."
version: "1.1.0"
author: "lost-rob0t"
category: "security"
tags: ["starintel", "security", "authorization", "api"]
---

# Authorization

## Objective

Prevent a validly authenticated caller, actor, or service from reading, searching, ingesting, modifying, exporting, or dispatching data outside its granted Starintel capabilities.

## Procedure

1. Define authorization actions independently from routes: document read, document ingest, document update, search, view query, target create, actor dispatch, event-log read, export, replay, and administration.
2. Default deny every action. Grant access by principal, tenant, dataset, document class, target actor, and operation as required.
3. Authenticate and authorize before revealing whether a document, dataset, actor, or route exists when existence itself is sensitive.
4. Apply dataset and document filtering inside CouchDB view/search queries or an equivalent pre-disclosure boundary. Do not fetch forbidden records and remove them afterward.
5. Bind ingest permission to the requested dataset and document type. A caller allowed to submit one dataset must not select another dataset in the body.
6. Bind target permission to the actor capability and target scope. Do not allow arbitrary actor names merely because the target schema validates.
7. Carry a minimal authorization context or internal service identity through RabbitMQ and actor messages. Do not trust caller-supplied authorization fields.
8. Restrict event logs, dead letters, raw artifacts, replay, and exports more strongly than ordinary derived documents because they may contain broad or sensitive context.
9. Record allow and deny decisions with request/correlation ID, principal, action, resource scope, policy version, and safe reason. Do not log credentials or full sensitive payloads.
10. Invalidate or version cached decisions when policy, membership, dataset ownership, or document classification changes.
11. Test cross-dataset access, enumeration, search leakage, target dispatch, replay, event-log access, stale cache, and confused-deputy service calls.

## Current Server Constraint

`starintel-server` currently has no complete authentication or authorization layer and its README says not to expose it to the web. Adding a route without a default-deny authorization boundary does not make the service publishable.

## Exit Criteria

- Every API, queue-triggered service action, actor capability, search, and export has a named authorization check.
- Forbidden data never enters a response or unauthorized side effect.
- Internal services cannot be used as confused deputies.
- Authorization decisions are testable, auditable, and policy-versioned.
