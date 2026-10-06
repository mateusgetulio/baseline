# Agent safety

## The honest guarantee

The server proves that a fresh preview of the exact operation happened before a booking was made. It cannot prove that a human read it.

What the server enforces:

- A booking needs a `preview_token` from `POST /v1/holds/{id}/preview`.
- The token is single use, issued to one key, bound to the hold, the customer and the price, and expires after 5 minutes or when the hold expires, whichever comes first.
- If the price or customer changes after the preview, the token is rejected and the client must preview again.
- However many times or however concurrently a token is sent, at most one booking exists.

What the server cannot enforce: that the person behind the agent saw the summary and agreed. That part lives in the client, which is why the MCP layer instructs it.

## What the MCP server tells the client

- `preview_booking`: "Show the summary to the user word for word and ask whether to book it. Do not call confirm_booking until the user explicitly says yes to this summary."
- `confirm_booking`: only after the user has explicitly said yes; annotated `destructiveHint: true` and `idempotentHint: true`.
- `hold_court`: holding consumes scarce inventory; hold only what the user asked for and release what they do not want.
- Read tools are annotated `readOnlyHint: true`.

Tools are listed according to the key's permissions from `/v1/me`. A key without `bookings.write` never sees `confirm_booking`; a read-only key sees only `whoami` and `search_availability`.

## Retries cannot double-book

`confirm_booking` derives its `Idempotency-Key` from the preview token. An agent that retries after a timeout gets the stored booking back instead of a second one. The sandbox can simulate exactly that failure with `X-Sandbox-Simulate: drop_response_after_commit`.

## Holds are reversible, not harmless

A hold takes a court off the market for everyone else. In this prototype that is limited by a short TTL (30 to 600 seconds), a cap of 3 active holds per key, and the release tool.

## Production controls not built here

- Hold limits per principal and per customer, beyond the one per-key limit implemented.
- Per-key rate limits.
- Abuse detection on hold churn (repeated hold and release cycles that keep inventory locked).

## Credit

The preview then confirm pattern comes from my earlier `wp-agent-action-review` repository.
