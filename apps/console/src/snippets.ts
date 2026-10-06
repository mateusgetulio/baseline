export interface Example {
  facilityId: number;
  courtId: number;
  customerId: number;
  date: string;
  startsAt: string;
  endsAt: string;
}

export function curlQuickstart(apiUrl: string, apiKey: string, example: Example | null): string {
  const lines = [
    `export BASELINE_KEY=${apiKey}`,
    `export BASELINE_URL=${apiUrl}`,
    "",
    "# Who am I",
    'curl -s "$BASELINE_URL/v1/me" -H "Authorization: Bearer $BASELINE_KEY"',
  ];
  if (!example) return lines.join("\n");
  const hold = JSON.stringify({
    court_id: example.courtId,
    customer_id: example.customerId,
    starts_at: example.startsAt,
    ends_at: example.endsAt,
    ttl_seconds: 300,
  });
  return [
    ...lines,
    "",
    "# Free slots tomorrow, 60 minutes",
    `curl -s "$BASELINE_URL/v1/availability?facility_id=${example.facilityId}&date=${example.date}&duration_minutes=60" \\`,
    '  -H "Authorization: Bearer $BASELINE_KEY"',
    "",
    "# Hold a court (note the hold id)",
    'curl -s -X POST "$BASELINE_URL/v1/holds" -H "Authorization: Bearer $BASELINE_KEY" \\',
    '  -H "Content-Type: application/json" -H "Idempotency-Key: $(uuidgen)" \\',
    `  -d '${hold}'`,
    "",
    "# Preview it (note the preview_token)",
    'curl -s -X POST "$BASELINE_URL/v1/holds/HOLD_ID/preview" -H "Authorization: Bearer $BASELINE_KEY"',
    "",
    "# Confirm, losing the response on purpose; run it again without the last header to get the stored 201",
    'curl -s -X POST "$BASELINE_URL/v1/bookings" -H "Authorization: Bearer $BASELINE_KEY" \\',
    '  -H "Content-Type: application/json" -H "Idempotency-Key: confirm-demo-1" \\',
    `  -d '{"preview_token":"PREVIEW_TOKEN"}' \\`,
    '  -H "X-Sandbox-Simulate: drop_response_after_commit"',
  ].join("\n");
}

export function mcpConfig(apiUrl: string, mcpEntry: string, apiKey: string, customerId: number | null): string {
  return JSON.stringify(
    {
      mcpServers: {
        baseline: {
          command: "node",
          args: [mcpEntry],
          env: {
            BASELINE_API_URL: apiUrl,
            BASELINE_API_KEY: apiKey,
            BASELINE_CUSTOMER_ID: String(customerId ?? ""),
          },
        },
      },
    },
    null,
    2,
  );
}

export function localDate(timeZone: string, daysAhead: number): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(
    new Date(Date.now() + daysAhead * 24 * 3600 * 1000),
  );
}
