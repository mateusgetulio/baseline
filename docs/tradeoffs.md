# Trade-offs

- **READ COMMITTED for mutations.** Correctness comes from row locks taken before the checks. Under MySQL's default REPEATABLE READ, a check that runs after a lock can still read an older snapshot; the hold race test fails without this.
- **Idempotency claim with INSERT IGNORE.** The claim is an insert under the unique index, checked by affected rows, instead of catching duplicate-key errors. The trilogy driver (2.13.1 on Ruby 4.0) returns a corrupted error message when many duplicate-key errors happen at once. To keep INSERT IGNORE from hiding other problems, paths longer than 255 characters are rejected before the claim.
- **4xx outcomes are stored under the Idempotency-Key.** A retry with the same key gets the same answer even if the slot frees up later; send a new key to try again. Unexpected 5xx outcomes are not stored.
- **Lazy expiry, no job system.** Expired holds are filtered by time on every read and write path. Nothing needs a background worker.
- **30 minute slot grid.** Holds must start on the grid that availability returns, so a client cannot block more slots than it sees.
- **Opening hours are not in the API.** They are wall-clock times, and the time contract allows no naked local times; availability already reflects them.
- **The MCP server books for one configured player** (`BASELINE_CUSTOMER_ID`). There is no customer lookup in the API, and an agent acting for one person should not choose who to book for.
- **Reset keeps ids.** It restores seed rows in place, so an MCP config written before a reset keeps working.
- **Integer ids and offset-free pagination.** Lists use an opaque cursor over the id. Ids are sequential, which is fine for a sandbox and not something I would expose in production.
- **The control plane is a demo surface.** One bootstrap secret, no users, no audit. It exists so a sandbox can be created and broken in seconds.
