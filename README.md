# Baseline

One booking contract, consumed identically by a developer with a sandbox key and by an AI agent through MCP. Consequential writes need a fresh preview token bound to the exact operation, the MCP layer tells clients to get an explicit yes from the user before using it, and no retry, race or lost response can create a second booking.

```bash
bin/setup && bin/dev
```

Then open http://localhost:5173 and press **Create sandbox**. Needs Ruby 3.2+, Node 22+ and Docker (MySQL 8.4 runs from `docker compose` on port 3307). To use your own MySQL 8 instead, set `BASELINE_SKIP_DOCKER=1` and `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD` before running the scripts. If ports 3000 or 5173 are taken, set `BASELINE_API_PORT` and `BASELINE_CONSOLE_PORT` in `.env`.

## Connect an agent

The console fills this block with your key and a seeded player. Paste it into any MCP client's server config:

```json
{
  "mcpServers": {
    "baseline": {
      "command": "node",
      "args": ["/path/to/baseline/apps/mcp/dist/src/index.js"],
      "env": {
        "BASELINE_API_URL": "http://localhost:3000",
        "BASELINE_API_KEY": "bl_test_...",
        "BASELINE_CUSTOMER_ID": "1"
      }
    }
  }
}
```

Then ask: "Find a court tomorrow at 10 for an hour at Harbor Point and book it."

## What it shows

- A small, correct REST API for court booking: scoped keys, availability in the facility's time zone, short holds, preview then confirm, mandatory idempotency, RFC 9457 errors, a hand-written OpenAPI document.
- A sandbox a developer can create, reset and break on purpose, including a simulated lost response.
- An MCP server that is just another client of the same API, so an agent gets the same permissions, idempotency and audit trail as any integrator.
- Tests that prove the safety claims under real concurrency.

## One data plane, one small control plane

- `/v1/*` is the data plane. curl, the console's examples and the MCP server all call it the same way. The MCP server has no database access and no private routes.
- `/sandbox/*` is a tiny control plane: create a sandbox, issue and revoke keys, reset, expire a hold, read the request log. It is a local demo surface protected by one bootstrap secret, `SANDBOX_ADMIN_TOKEN`, which `bin/setup` writes to `.env`. It is not real console auth. The console's dev server adds that secret to its `/sandbox` calls so it never reaches the browser, which means anything that can reach the console's local port can use the control plane.

See [docs/architecture.md](docs/architecture.md), [docs/openapi.yaml](docs/openapi.yaml) and [docs/errors.md](docs/errors.md).

## Agent safety

The server proves that a fresh preview of the exact operation happened before a booking: the token is single use, bound to the hold, customer and price, and expires in 5 minutes. It cannot prove that a human read that preview. That is why the MCP tool descriptions tell the client to show the summary and wait for an explicit yes, and why `confirm_booking` is annotated as destructive. Holds are not harmless either: they take scarce inventory off the market, so they are short, capped at 3 active holds per key, and released or expired quickly. Details in [docs/agent-safety.md](docs/agent-safety.md).

## Proofs

Each test fails if its guarantee is removed (checked by breaking each guard once). The concurrency tests run real parallel threads against MySQL, without transactional fixtures.

| Claim | Test | Run it |
|---|---|---|
| 20 concurrent holds on one slot from 20 keys: one winner | Hold race | `cd apps/api && bundle exec rspec spec/concurrency/hold_race_spec.rb` |
| 10 concurrent confirms of one preview token: one booking | Confirm race | `cd apps/api && bundle exec rspec spec/concurrency/confirm_race_spec.rb` |
| 10 concurrent requests with one Idempotency-Key: executed once | Idempotency race | `cd apps/api && bundle exec rspec spec/requests/idempotency_spec.rb -e "executes the operation once"` |
| A booking whose response is lost is replayed, not repeated | Lost response | `cd apps/api && bundle exec rspec spec/requests/lost_response_spec.rb` |
| An agent books exactly once over MCP; a read-only key sees no write tools | MCP end to end | `cd apps/mcp && npm run test:e2e` |

All Rails specs: `cd apps/api && bundle exec rspec`. Main responses are validated against `docs/openapi.yaml` in the request specs.

To watch a hold race against your own running sandbox, with the key and player id from the console (it sends all 20 holds from one key, so it is a demo; the RSpec hold race with 20 keys is the proof):

```bash
BASELINE_KEY=bl_test_... BASELINE_CUSTOMER_ID=1 node scripts/hold_race.mjs
```

It fires 20 concurrent holds at one slot and prints `201 x1, 409 slot_unavailable x19`; the console's request table shows all 20.

## What I would add next

Rate limits per key, webhook delivery, SDK generation from the OpenAPI document, date-based API versioning, and usage analytics per key.

## What it deliberately does not do

Payments, cancellation, live keys and real console auth.

## License

MIT
