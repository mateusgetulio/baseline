# Errors

Every error response is an RFC 9457 Problem Details body with the media type `application/problem+json`:

```json
{
  "type": "https://baseline.test/docs/errors#slot_unavailable",
  "title": "Slot is not available",
  "status": 409,
  "detail": "The court is already held or booked for part of this window.",
  "code": "slot_unavailable"
}
```

Branch on `code`. It is stable; `title` and `detail` are for people and may change. Validation errors add `invalid_params`, a list of `{ "name", "reason" }` objects.

The outcome of a mutation that ran, success or 4xx, is stored under its `Idempotency-Key` and replayed on every retry with that key. To try again after a `validation_failed`, `slot_unavailable`, `hold_limit_reached`, `hold_not_active` or `preview_token_*` response, send a new `Idempotency-Key`.

| Code | Status | When |
|---|---|---|
| `unauthorized` | 401 | The `Authorization: Bearer` key is missing, malformed, unknown or revoked. |
| `permission_denied` | 403 | The key is valid but lacks the permission the route needs. |
| `not_found` | 404 | The route does not exist, or the resource does not exist or belongs to another sandbox. A hold owned by another key also returns this. |
| `malformed_request` | 400 | The request body is not valid JSON. |
| `validation_failed` | 422 | One or more parameters are missing or invalid; see `invalid_params`. Also returned for a mutation path longer than 255 characters. |
| `idempotency_key_missing` | 400 | A mutation was sent without an `Idempotency-Key` header. |
| `idempotency_key_reused` | 409 | The `Idempotency-Key` was already used by this key for a different method, path or body. |
| `idempotency_in_progress` | 409 | A request with the same `Idempotency-Key` is still running. Retry later to get its stored response. |
| `slot_unavailable` | 409 | Another active hold or a confirmed booking overlaps the requested window. The response never says who holds it. |
| `hold_limit_reached` | 409 | The key already has 3 active holds. Release one, book one, or let one expire. |
| `hold_not_active` | 409 | The hold was already released, expired or converted into a booking. |
| `preview_token_missing` | 422 | `POST /v1/bookings` was sent without a `preview_token`. |
| `preview_token_invalid` | 422 | The `preview_token` is unknown, or was issued to a different key. |
| `preview_token_expired` | 410 | The token is older than 5 minutes, or its hold's expiry passed. Preview the hold again. |
| `preview_token_used` | 409 | The token already confirmed a booking. A token confirms at most one booking. |
| `preview_token_mismatch` | 409 | The hold's customer or price changed after the preview, so the token no longer describes the booking. Preview again. |
| `internal_error` | 500 | Unexpected server error. Retrying with the same `Idempotency-Key` is safe: failed executions are not stored. |
