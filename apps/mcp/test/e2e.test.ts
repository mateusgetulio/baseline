import assert from "node:assert/strict";
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { dirname, resolve } from "node:path";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const here = dirname(fileURLToPath(import.meta.url));
const mcpRoot = resolve(here, "../..");
const apiRoot = resolve(mcpRoot, "../api");
const port = process.env.BASELINE_E2E_PORT ?? "3100";
const apiUrl = `http://127.0.0.1:${port}`;
const adminToken = `e2e-${randomBytes(8).toString("hex")}`;

let rails: ChildProcess | undefined;

interface CreatedSandbox {
  sandbox: { id: number };
  key: { api_key: string };
  customers: { id: number; name: string }[];
}

async function admin<T>(method: string, path: string, body?: unknown): Promise<T> {
  const response = await fetch(`${apiUrl}${path}`, {
    method,
    headers: { Authorization: `Bearer ${adminToken}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.ok(response.ok, `${method} ${path} returned ${response.status}`);
  return (await response.json()) as T;
}

async function connect(apiKey: string, customerId: number): Promise<Client> {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [resolve(mcpRoot, "dist/src/index.js")],
    env: {
      PATH: process.env.PATH ?? "",
      BASELINE_API_URL: apiUrl,
      BASELINE_API_KEY: apiKey,
      BASELINE_CUSTOMER_ID: String(customerId),
    },
  });
  const client = new Client({ name: "baseline-e2e", version: "0.1.0" });
  await client.connect(transport);
  return client;
}

function payload<T>(result: Awaited<ReturnType<Client["callTool"]>>): T {
  const content = result.content as { type: string; text: string }[];
  assert.equal(result.isError ?? false, false, content[0]?.text);
  return JSON.parse(content[0]!.text) as T;
}

function bookingsInSandbox(sandboxId: number): number {
  const output = execFileSync(
    "bin/rails",
    ["runner", `print Booking.where(sandbox_id: ${sandboxId}).count`],
    { cwd: apiRoot, env: { ...process.env, RAILS_ENV: "test" }, encoding: "utf8" },
  );
  return Number(output.trim().split("\n").pop());
}

function tomorrowIn(timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(
    new Date(Date.now() + 24 * 3600 * 1000),
  );
}

before(async () => {
  if (!process.env.BASELINE_E2E_EXTERNAL_API) {
    rails = spawn("bin/rails", ["server", "-p", port, "-b", "127.0.0.1", "-P", "tmp/pids/e2e.pid"], {
      cwd: apiRoot,
      env: { ...process.env, RAILS_ENV: "test", SANDBOX_ADMIN_TOKEN: adminToken },
      stdio: "ignore",
    });
  }
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await fetch(`${apiUrl}/v1/me`);
      if (response.status === 401) return;
    } catch {
      await new Promise((done) => setTimeout(done, 500));
    }
  }
  throw new Error(`API did not start on ${apiUrl}`);
});

after(() => {
  rails?.kill("SIGTERM");
});

test("Test 10: an agent searches, holds, previews and confirms exactly one booking over MCP", async () => {
  const created = await admin<CreatedSandbox>("POST", "/sandbox", { name: "MCP e2e" });
  const customer = created.customers[0]!;
  const client = await connect(created.key.api_key, customer.id);
  try {
    const names = (await client.listTools()).tools.map((tool) => tool.name).sort();
    assert.deepEqual(names, [
      "confirm_booking",
      "hold_court",
      "preview_booking",
      "release_hold",
      "search_availability",
      "whoami",
    ]);

    const search = payload<{ facility: { id: number; time_zone: string }; courts: { court_id: number; name: string; slots: { starts_at: string; ends_at: string }[] }[] }[]>(
      await client.callTool({
        name: "search_availability",
        arguments: {
          facility: "Harbor Point",
          date: tomorrowIn("America/New_York"),
          duration_minutes: 60,
          earliest: "10:00",
          latest: "10:00",
        },
      }),
    );
    const court = search[0]!.courts.find((c) => c.name === "Court 2")!;
    assert.equal(court.slots.length, 1);
    const slot = court.slots[0]!;
    assert.match(slot.starts_at, /T10:00:00[+-]\d{2}:\d{2}$/);

    const hold = payload<{ id: number; status: string }>(
      await client.callTool({
        name: "hold_court",
        arguments: { court_id: court.court_id, starts_at: slot.starts_at, ends_at: slot.ends_at },
      }),
    );
    assert.equal(hold.status, "active");

    const preview = payload<{ summary: string; preview_token: string; price_cents: number }>(
      await client.callTool({ name: "preview_booking", arguments: { hold_id: hold.id } }),
    );
    assert.match(preview.summary, /Court 2/);
    assert.match(preview.summary, new RegExp(customer.name));

    const booking = payload<{ id: number; status: string; price_cents: number }>(
      await client.callTool({ name: "confirm_booking", arguments: { preview_token: preview.preview_token } }),
    );
    assert.equal(booking.status, "confirmed");
    assert.equal(booking.price_cents, preview.price_cents);

    const retried = payload<{ id: number }>(
      await client.callTool({ name: "confirm_booking", arguments: { preview_token: preview.preview_token } }),
    );
    assert.equal(retried.id, booking.id);
    assert.equal(bookingsInSandbox(created.sandbox.id), 1);

    const log = await admin<{ data: { path: string; client: string | null; replayed: boolean }[] }>(
      "GET",
      `/sandbox/${created.sandbox.id}/requests`,
    );
    assert.ok(log.data.length > 0);
    assert.ok(log.data.every((entry) => entry.client === "mcp"));
    assert.equal(log.data.filter((entry) => entry.path === "/v1/bookings" && entry.replayed).length, 1);
  } finally {
    await client.close();
  }
});

test("Test 10: a read-only key sees no write tools", async () => {
  const created = await admin<CreatedSandbox>("POST", "/sandbox", { name: "MCP e2e read-only" });
  const readOnly = await admin<{ api_key: string }>("POST", `/sandbox/${created.sandbox.id}/keys`, {
    permissions: ["availability.read"],
  });
  const client = await connect(readOnly.api_key, created.customers[0]!.id);
  try {
    const tools = (await client.listTools()).tools;
    assert.deepEqual(tools.map((tool) => tool.name).sort(), ["search_availability", "whoami"]);
    assert.ok(tools.every((tool) => tool.annotations?.readOnlyHint === true));
  } finally {
    await client.close();
  }
});

test("Test 10: tool annotations and confirmation instructions", async () => {
  const created = await admin<CreatedSandbox>("POST", "/sandbox", { name: "MCP e2e annotations" });
  const client = await connect(created.key.api_key, created.customers[0]!.id);
  try {
    const tools = Object.fromEntries((await client.listTools()).tools.map((tool) => [tool.name, tool]));
    for (const name of ["whoami", "search_availability", "preview_booking"]) {
      assert.equal(tools[name]!.annotations?.readOnlyHint, true, name);
    }
    assert.equal(tools.confirm_booking!.annotations?.destructiveHint, true);
    assert.equal(tools.confirm_booking!.annotations?.idempotentHint, true);
    assert.match(tools.confirm_booking!.description!, /explicitly said yes/);
    assert.match(tools.preview_booking!.description!, /Show the summary to the user/);
    for (const tool of Object.values(tools)) assert.doesNotMatch(tool.description ?? "", /—/);
  } finally {
    await client.close();
  }
});
