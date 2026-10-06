import { createHash, randomUUID } from "node:crypto";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import { ApiError, type BaselineApi, type Facility, type Me } from "./api.js";

export interface ServerConfig {
  customerId: number;
}

const INSTANT = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/)
  .describe("RFC 3339 instant with an offset, copied exactly from a search_availability slot.");
const LOCAL_TIME = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);

export function confirmIdempotencyKey(previewToken: string): string {
  return `confirm-${createHash("sha256").update(previewToken).digest("hex").slice(0, 40)}`;
}

function ok(value: unknown): CallToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

async function call(work: () => Promise<unknown>): Promise<CallToolResult> {
  try {
    return ok(await work());
  } catch (error) {
    if (error instanceof ApiError) {
      return { isError: true, content: [{ type: "text", text: JSON.stringify(error.problem, null, 2) }] };
    }
    throw error;
  }
}

function localMinutes(instant: string): number {
  const match = /T(\d{2}):(\d{2})/.exec(instant);
  return match ? Number(match[1]) * 60 + Number(match[2]) : 0;
}

function toMinutes(time: string): number {
  const [hours, minutes] = time.split(":").map(Number);
  return (hours ?? 0) * 60 + (minutes ?? 0);
}

async function resolveFacilities(api: BaselineApi, facility: number | string | undefined): Promise<Facility[]> {
  const all = await api.facilities();
  if (facility === undefined) return all;
  const wanted = String(facility).toLowerCase();
  const matches = all.filter((f) => String(f.id) === wanted || f.name.toLowerCase().includes(wanted));
  if (matches.length === 0) {
    throw new ApiError({
      type: "about:blank",
      title: "Facility not found",
      status: 404,
      detail: `No facility matches "${facility}". Known facilities: ${all.map((f) => `${f.id} ${f.name}`).join(", ")}.`,
      code: "not_found",
    });
  }
  return matches;
}

export function buildServer(api: BaselineApi, me: Me, config: ServerConfig): McpServer {
  const server = new McpServer({ name: "baseline", version: "0.1.0" });
  const can = (permission: Me["permissions"][number]) => me.permissions.includes(permission);

  server.registerTool(
    "whoami",
    {
      title: "Who am I",
      description:
        "Shows which sandbox API key this server uses, its sandbox and its permissions, and the customer it books for. Tools appear only when the key has the permission they need.",
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    () => call(async () => ({ ...(await api.me()), customer_id: config.customerId })),
  );

  if (can("availability.read")) {
    server.registerTool(
      "search_availability",
      {
        title: "Search court availability",
        description:
          "Lists free court slots for one date. The date and the optional earliest and latest times are wall-clock times at the facility, in its own time zone. Every returned slot is an RFC 3339 instant with an offset; pass those values unchanged to hold_court. Leave facility out to search every facility.",
        inputSchema: {
          facility: z
            .union([z.number().int(), z.string()])
            .optional()
            .describe("Facility id, or part of its name. Omit to search all facilities."),
          date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe("Facility-local date, YYYY-MM-DD."),
          duration_minutes: z.number().int().min(30).max(240).multipleOf(30).default(60),
          earliest: LOCAL_TIME.optional().describe("Earliest local start time, HH:MM."),
          latest: LOCAL_TIME.optional().describe("Latest local start time, HH:MM."),
        },
        annotations: { readOnlyHint: true, openWorldHint: false },
      },
      ({ facility, date, duration_minutes, earliest, latest }) =>
        call(async () => {
          const facilities = await resolveFacilities(api, facility);
          const results = [];
          for (const found of facilities) {
            const availability = await api.availability(found.id, date, duration_minutes);
            results.push({
              facility: found,
              date: availability.date,
              duration_minutes: availability.duration_minutes,
              courts: availability.courts.map((court) => ({
                ...court,
                slots: court.slots.filter((slot) => {
                  const start = localMinutes(slot.starts_at);
                  return (!earliest || start >= toMinutes(earliest)) && (!latest || start <= toMinutes(latest));
                }),
              })),
            });
          }
          return results;
        }),
    );
  }

  if (can("holds.write")) {
    server.registerTool(
      "hold_court",
      {
        title: "Hold a court",
        description:
          "Reserves one court window for a short time so nobody else can take it while the user decides. This consumes scarce inventory: hold only what the user asked for, keep the TTL short, and release holds the user does not want. A key can have at most 3 active holds. Holding does not book anything.",
        inputSchema: {
          court_id: z.number().int(),
          starts_at: INSTANT,
          ends_at: INSTANT,
          ttl_seconds: z.number().int().min(30).max(600).default(120).describe("How long the hold lasts, 30 to 600 seconds."),
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
      },
      ({ court_id, starts_at, ends_at, ttl_seconds }) =>
        call(() =>
          api.createHold(
            { court_id, customer_id: config.customerId, starts_at, ends_at, ttl_seconds },
            `hold-${randomUUID()}`,
          ),
        ),
    );

    server.registerTool(
      "release_hold",
      {
        title: "Release a hold",
        description: "Gives a held court window back so others can book it. Use it when the user does not want the slot.",
        inputSchema: { hold_id: z.number().int() },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
      },
      ({ hold_id }) => call(() => api.releaseHold(hold_id, `release-${hold_id}`)),
    );
  }

  if (can("bookings.read")) {
    server.registerTool(
      "preview_booking",
      {
        title: "Preview a booking",
        description:
          "Prepares the booking for a hold without making it. Returns the price, a plain-language summary and a single-use preview_token that expires in 5 minutes or when the hold expires. Show the summary to the user word for word and ask whether to book it. Do not call confirm_booking until the user explicitly says yes to this summary.",
        inputSchema: { hold_id: z.number().int() },
        annotations: { readOnlyHint: true, openWorldHint: false },
      },
      ({ hold_id }) => call(() => api.preview(hold_id)),
    );
  }

  if (can("bookings.write")) {
    server.registerTool(
      "confirm_booking",
      {
        title: "Confirm a booking",
        description:
          "Books the court for real. Only call this after you have shown the user the preview_booking summary and the user has explicitly said yes to it in this conversation. Pass the preview_token from that preview. Retrying with the same token is safe: it never creates a second booking.",
        inputSchema: { preview_token: z.string().min(1) },
        annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
      },
      ({ preview_token }) => call(() => api.confirm(preview_token, confirmIdempotencyKey(preview_token))),
    );
  }

  return server;
}
