export type Permission = "availability.read" | "holds.write" | "bookings.read" | "bookings.write";

export const ALL_PERMISSIONS: Permission[] = ["availability.read", "holds.write", "bookings.read", "bookings.write"];

export interface Problem {
  code: string;
  title: string;
  detail: string;
  status: number;
}

export class ApiError extends Error {
  constructor(readonly problem: Problem) {
    super(`${problem.code}: ${problem.detail}`);
  }
}

export interface Key {
  id: number;
  permissions: Permission[];
  revoked_at: string | null;
  api_key?: string;
}

export interface CreatedSandbox {
  sandbox: { id: number; name: string };
  key: Key;
  customers: { id: number; name: string }[];
}

export interface Facility {
  id: number;
  name: string;
  time_zone: string;
}

export interface Slot {
  starts_at: string;
  ends_at: string;
}

export interface Availability {
  courts: { court_id: number; name: string; slots: Slot[] }[];
}

export interface RequestLog {
  id: number;
  method: string;
  path: string;
  status: number;
  code: string | null;
  replayed: boolean;
  client: string | null;
  created_at: string;
}

async function send<T>(method: string, path: string, init: { body?: unknown; apiKey?: string } = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (init.body !== undefined) headers["Content-Type"] = "application/json";
  if (init.apiKey) {
    headers.Authorization = `Bearer ${init.apiKey}`;
    headers["X-Client"] = "console";
  }
  const response = await fetch(path, {
    method,
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const parsed: unknown = await response.json();
  if (!response.ok) throw new ApiError(parsed as Problem);
  return parsed as T;
}

export const controlPlane = {
  createSandbox: (name: string) => send<CreatedSandbox>("POST", "/sandbox", { body: { name } }),
  createKey: (sandboxId: number, permissions: Permission[]) =>
    send<Key>("POST", `/sandbox/${sandboxId}/keys`, { body: { permissions } }),
  reset: (sandboxId: number) => send<unknown>("POST", `/sandbox/${sandboxId}/reset`),
  expireHold: (sandboxId: number, holdId: number) =>
    send<{ id: number; status: string }>("POST", `/sandbox/${sandboxId}/holds/${holdId}/expire`),
  requests: (sandboxId: number) => send<{ data: RequestLog[] }>("GET", `/sandbox/${sandboxId}/requests`),
};

export const dataPlane = {
  me: (apiKey: string) => send<{ permissions: Permission[] }>("GET", "/v1/me", { apiKey }),
  facilities: (apiKey: string) => send<{ data: Facility[] }>("GET", "/v1/facilities", { apiKey }),
  availability: (apiKey: string, facilityId: number, date: string) =>
    send<Availability>(
      "GET",
      `/v1/availability?${new URLSearchParams({ facility_id: String(facilityId), date, duration_minutes: "60" })}`,
      { apiKey },
    ),
};
