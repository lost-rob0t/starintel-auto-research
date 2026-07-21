---
name: "api-design"
description: "Add a Starintel Ningle endpoint with versioning, validation, authorization, and tests."
version: "1.1.0"
author: "lost-rob0t"
category: "product"
tags: ["starintel", "product", "api-design", "ningle"]
---

# API Design

## Objective

Add or change a Starintel HTTP endpoint without exposing raw prototype behavior, duplicating routes, bypassing schema validation, or coupling the handler directly to every backend detail.

## Procedure

1. Inspect `starintel-server/source/frontends/http-api.lisp`, its package, database helpers, Rabbit producers, schema constructors, and existing API documentation.
2. Define the endpoint contract before coding:
   - method and versioned path;
   - authentication and authorization action;
   - path, query, and JSON body schema;
   - success and error statuses;
   - response schema and pagination;
   - idempotency behavior;
   - rate and size limits;
   - database, queue, or actor side effects.
3. Use a versioned namespace such as `/v1` for a public contract. Treat current unversioned routes as prototype compatibility paths until migrated.
4. Verify method/path uniqueness. The current source defines `/dataset-size` twice; new work must detect and reject duplicate registrations.
5. Extract parsing, validation, authorization, business logic, and response formatting into testable functions rather than one route lambda.
6. Authenticate and authorize before database queries, Rabbit publishing, actor dispatch, or information-revealing validation.
7. Set JSON content type and explicit HTTP status. Error helpers must not return every failure as status 200.
8. Return stable error objects with code, message, request/correlation ID, and safe field errors. Do not expose Lisp conditions or tracebacks.
9. Bound `limit`, `skip`, body size, search complexity, timeouts, and queue publication work.
10. For ingest routes, validate body `dtype`, path suffix, routing key, and Rabbit type property as one contract.
11. For query routes, apply authorization inside the query plan so forbidden records never enter the result set.
12. Update API documentation and add route, handler, authorization, validation, and backend integration tests.

## Production Gate

The server README currently states that the project is experimental and must not be exposed to the web. Do not describe an endpoint as public or production-ready until authentication, authorization, TLS deployment, rate limits, safe errors, and integration tests exist.

## Exit Criteria

- Method/path registration is unique and versioned.
- Input, authorization, response, and failure contracts are tested.
- Queue and database side effects are idempotent and observable.
- No raw traceback, secret, or unauthorized document escapes.
- Documentation matches the implemented endpoint exactly.
