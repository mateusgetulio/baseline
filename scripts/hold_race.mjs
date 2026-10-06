import { randomUUID } from "node:crypto";

const baseUrl = process.env.BASELINE_URL ?? "http://localhost:3000";
const apiKey = process.env.BASELINE_KEY;
const customerId = Number(process.env.BASELINE_CUSTOMER_ID);
const count = Number(process.argv[2] ?? 20);

if (!apiKey || !customerId) {
  console.error("Set BASELINE_KEY and BASELINE_CUSTOMER_ID (both shown in the console), and BASELINE_URL if not on port 3000.");
  process.exit(2);
}

const headers = { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" };

async function get(path) {
  const response = await fetch(new URL(path, baseUrl), { headers });
  if (!response.ok) throw new Error(`GET ${path}: ${response.status} ${await response.text()}`);
  return response.json();
}

const facility = (await get("/v1/facilities")).data[0];
const date = new Intl.DateTimeFormat("en-CA", { timeZone: facility.time_zone }).format(new Date(Date.now() + 86400000));
const availability = await get(`/v1/availability?facility_id=${facility.id}&date=${date}&duration_minutes=60`);
const court = availability.courts[0];
const slot = court.slots.find((s) => s.starts_at.includes("T10:00")) ?? court.slots[0];
if (!slot) throw new Error(`${court.name} has no free slot on ${date}.`);

console.log(`${count} concurrent POST /v1/holds for ${court.name}, ${facility.name}, ${slot.starts_at} to ${slot.ends_at}`);

const body = JSON.stringify({
  court_id: court.court_id,
  customer_id: customerId,
  starts_at: slot.starts_at,
  ends_at: slot.ends_at,
  ttl_seconds: 60,
});
const results = await Promise.all(
  Array.from({ length: count }, async () => {
    const response = await fetch(new URL("/v1/holds", baseUrl), {
      method: "POST",
      headers: { ...headers, "Idempotency-Key": randomUUID() },
      body,
    });
    const parsed = await response.json();
    return response.ok ? `${response.status}` : `${response.status} ${parsed.code}`;
  }),
);

const tally = Object.entries(Object.groupBy(results, (r) => r)).map(([outcome, list]) => `${outcome} x${list.length}`);
console.log(tally.join(", "));
const winners = results.filter((r) => r === "201").length;
console.log(winners === 1 ? "One winner. The hold expires in 60 seconds." : `Expected one winner, got ${winners}.`);
process.exit(winners === 1 ? 0 : 1);
