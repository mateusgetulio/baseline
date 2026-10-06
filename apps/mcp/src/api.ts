export type Permission = "availability.read" | "holds.write" | "bookings.read" | "bookings.write";

export interface Me {
  key_id: number;
  sandbox: { id: number; name: string };
  permissions: Permission[];
}

export interface Problem {
  type: string;
  title: string;
  status: number;
  detail: string;
  code: string;
  invalid_params?: { name: string; reason: string }[];
}

export class ApiError extends Error {
  constructor(readonly problem: Problem) {
    super(`${problem.code}: ${problem.detail}`);
  }
}

export interface Facility {
  id: number;
  name: string;
  time_zone: string;
}

export interface Slot {
  starts_at: string;
  ends_at: string;
  price_cents: number;
  currency: string;
}

export interface Availability {
  facility_id: number;
  date: string;
  time_zone: string;
  duration_minutes: number;
  courts: { court_id: number; name: string; sport: string; slots: Slot[] }[];
}

export class BaselineApi {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  me(): Promise<Me> {
    return this.request("GET", "/v1/me");
  }

  async facilities(): Promise<Facility[]> {
    const page = await this.request<{ data: Facility[] }>("GET", "/v1/facilities?limit=100");
    return page.data;
  }

  availability(facilityId: number, date: string, durationMinutes: number): Promise<Availability> {
    const query = new URLSearchParams({
      facility_id: String(facilityId),
      date,
      duration_minutes: String(durationMinutes),
    });
    return this.request("GET", `/v1/availability?${query}`);
  }

  createHold(body: Record<string, unknown>, idempotencyKey: string): Promise<unknown> {
    return this.request("POST", "/v1/holds", body, idempotencyKey);
  }

  releaseHold(holdId: number, idempotencyKey: string): Promise<unknown> {
    return this.request("DELETE", `/v1/holds/${holdId}`, undefined, idempotencyKey);
  }

  preview(holdId: number): Promise<unknown> {
    return this.request("POST", `/v1/holds/${holdId}/preview`);
  }

  confirm(previewToken: string, idempotencyKey: string): Promise<unknown> {
    return this.request("POST", "/v1/bookings", { preview_token: previewToken }, idempotencyKey);
  }

  private async request<T>(method: string, path: string, body?: unknown, idempotencyKey?: string): Promise<T> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      Accept: "application/json",
      "X-Client": "mcp",
      "User-Agent": "baseline-mcp/0.1.0",
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

    const response = await fetch(new URL(path, this.baseUrl), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    const parsed: unknown = text ? JSON.parse(text) : {};
    if (!response.ok) throw new ApiError(parsed as Problem);
    return parsed as T;
  }
}
