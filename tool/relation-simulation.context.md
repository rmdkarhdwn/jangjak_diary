# Flutter relation HTTP integration

Created 2026-10-26. Reuses the sibling backend's existing Postman Anthropic
Messages fixture; no new mock or cloud binding was created.

## Purpose

Exercise the production Dart HTTP client, actual Fastify service and actual SDK
against the backend-owned provider fixture, including upstream errors.

## Execution

1. In `../jangjak_diary_backend`, run `postman simulation run postman/simulations/relations-local/relations-local.sim.yaml --port 4900 --output ndjson --no-history`.
2. In this app, run `../jangjak_diary_backend/node_modules/.bin/tsx tool/relation_simulation_server.mts`.
3. Run `flutter test --no-pub test_integration/relation_api_http_test.dart`.
4. Stop both servers with Ctrl-C. No provider credentials are read.

## Assumptions

The backend must be installed next to this app, or supplied with `BACKEND_DIR`.
The fixture requires synthetic IDs `flutter`/`game` and its documented log text.
Its origin and the unavailable owner-cloud search are documented in the backend's
`postman/simulations/relations-local/relations-local.context.md`.
This proves transport and error handling against a fixed fixture, not live Haiku
access, inference quality or physical-device LAN reachability.

## Observations

<!-- begin:observations -->
2026-10-26: the five-test HTTP suite passed with persistent caching. Only the
initial analysis, the update after three new records, and the injected upstream
failure reached `anthropic` in the cache scenario; reopening, identical inputs,
and two new records emitted no extra upstream request. The only member served
all expected traffic; none stayed silent. Its isolated backend uses a 20-call
in-memory test budget so the production five-call budget cannot contaminate it.
2026-10-26: all four HTTP integration tests passed after adding recordless
candidate identities and source-only topic evidence. The sole `anthropic`
member served shared-log, explicit-reference, upstream-500 and malformed-JSON
calls. The reference quote mapped only to the book record, with no fabricated
guitar entry. The single-interest/no-candidate empty path still bypassed AI.
2026-10-26: all three integration tests passed. The only provider member,
`anthropic`, handled three POST /v1/messages calls (valid 200, simulated 500,
malformed output 200). The client received score 0.66, LLM_API_ERROR and
INVALID_LLM_RESPONSE respectively. The one-interest empty result bypassed the
provider as specified. No member stayed silent.
<!-- end:observations -->
