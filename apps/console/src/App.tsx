import { useEffect, useState } from "react";
import {
  ALL_PERMISSIONS,
  ApiError,
  controlPlane,
  dataPlane,
  type CreatedSandbox,
  type Key,
  type Permission,
  type RequestLog,
} from "./api";
import { curlQuickstart, localDate, mcpConfig, type Example } from "./snippets";

type Tab = "curl" | "mcp";

function message(error: unknown): string {
  return error instanceof ApiError ? `${error.problem.code}: ${error.problem.detail}` : String(error);
}

async function buildExample(apiKey: string, customerId: number): Promise<Example | null> {
  const facility = (await dataPlane.facilities(apiKey)).data[0];
  if (!facility) return null;
  const date = localDate(facility.time_zone, 1);
  const availability = await dataPlane.availability(apiKey, facility.id, date);
  const court = availability.courts[1] ?? availability.courts[0];
  const slot = court?.slots.find((s) => s.starts_at.includes("T10:00")) ?? court?.slots[0];
  if (!court || !slot) return null;
  return { facilityId: facility.id, courtId: court.court_id, customerId, date, startsAt: slot.starts_at, endsAt: slot.ends_at };
}

function CopyBlock({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="copy-block">
      <button
        className="copy-button"
        onClick={() => {
          void navigator.clipboard.writeText(text).then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1500);
          });
        }}
      >
        {copied ? "Copied" : `Copy ${label}`}
      </button>
      <pre>{text}</pre>
    </div>
  );
}

export function App() {
  const [created, setCreated] = useState<CreatedSandbox | null>(null);
  const [keys, setKeys] = useState<Key[]>([]);
  const [activeKeyId, setActiveKeyId] = useState<number | null>(null);
  const [customerId, setCustomerId] = useState<number | null>(null);
  const [example, setExample] = useState<Example | null>(null);
  const [requests, setRequests] = useState<RequestLog[]>([]);
  const [tab, setTab] = useState<Tab>("mcp");
  const [newKeyPermissions, setNewKeyPermissions] = useState<Permission[]>(["availability.read"]);
  const [holdId, setHoldId] = useState("");
  const [status, setStatus] = useState<{ kind: "ok" | "error"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const sandboxId = created?.sandbox.id;
  const activeKey = keys.find((k) => k.id === activeKeyId) ?? null;

  useEffect(() => {
    if (sandboxId === undefined) return;
    let cancelled = false;
    const poll = () =>
      controlPlane
        .requests(sandboxId)
        .then((page) => {
          if (!cancelled) setRequests(page.data);
        })
        .catch(() => undefined);
    void poll();
    const timer = setInterval(poll, 2000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [sandboxId]);

  async function run(work: () => Promise<string>) {
    setBusy(true);
    try {
      setStatus({ kind: "ok", text: await work() });
    } catch (error) {
      setStatus({ kind: "error", text: message(error) });
    } finally {
      setBusy(false);
    }
  }

  const createSandbox = () =>
    run(async () => {
      const result = await controlPlane.createSandbox("Console sandbox");
      const apiKey = result.key.api_key!;
      const me = await dataPlane.me(apiKey);
      const firstCustomer = result.customers[0]?.id ?? null;
      setCreated(result);
      setKeys([{ ...result.key, permissions: me.permissions }]);
      setActiveKeyId(result.key.id);
      setCustomerId(firstCustomer);
      setRequests([]);
      setExample(firstCustomer === null ? null : await buildExample(apiKey, firstCustomer));
      return `Sandbox ${result.sandbox.id} created with seed data.`;
    });

  const issueKey = () =>
    run(async () => {
      if (sandboxId === undefined) throw new Error("Create a sandbox first.");
      const key = await controlPlane.createKey(sandboxId, newKeyPermissions);
      setKeys((current) => [...current, key]);
      setActiveKeyId(key.id);
      return `Key ${key.id} issued with ${key.permissions.join(", ")}.`;
    });

  const reset = () =>
    run(async () => {
      if (sandboxId === undefined) throw new Error("Create a sandbox first.");
      await controlPlane.reset(sandboxId);
      return "Sandbox reset: holds and bookings cleared, seed data restored.";
    });

  const expire = () =>
    run(async () => {
      if (sandboxId === undefined) throw new Error("Create a sandbox first.");
      const hold = await controlPlane.expireHold(sandboxId, Number(holdId));
      return `Hold ${hold.id} is now ${hold.status}.`;
    });

  const apiKey = activeKey?.api_key ?? "";

  return (
    <div className="page">
      <header className="masthead">
        <div>
          <h1>Baseline Console</h1>
          <p className="lede">A court booking sandbox for developers and AI agents. One data plane: curl, this console and MCP all call /v1.</p>
        </div>
        <button className="primary" onClick={createSandbox} disabled={busy}>
          {created ? "Create another sandbox" : "Create sandbox"}
        </button>
      </header>

      {status && <div className={`status ${status.kind}`}>{status.text}</div>}

      {!created ? (
        <section className="empty">
          <p>Create a sandbox to get a seeded club, an API key shown once, and copy-ready curl and MCP setups.</p>
        </section>
      ) : (
        <>
          <div className="grid">
            <section className="card">
              <h2>
                Sandbox {created.sandbox.id} <span className="muted">{created.sandbox.name}</span>
              </h2>
              <div className="keys">
                {keys.map((key) => (
                  <label key={key.id} className={`key-row ${key.id === activeKeyId ? "active" : ""}`}>
                    <input
                      type="radio"
                      name="active-key"
                      checked={key.id === activeKeyId}
                      onChange={() => setActiveKeyId(key.id)}
                    />
                    <span className="key-id">Key {key.id}</span>
                    <span className="perms">
                      {key.permissions.map((p) => (
                        <span key={p} className="perm">
                          {p}
                        </span>
                      ))}
                    </span>
                  </label>
                ))}
              </div>
              <p className="secret-label">Secret for the selected key, shown only in this session:</p>
              <code className="secret">{apiKey}</code>

              <div className="field-row">
                <span className="field-label">Book for</span>
                <select value={customerId ?? ""} onChange={(e) => setCustomerId(Number(e.target.value))}>
                  {created.customers.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} (customer {c.id})
                    </option>
                  ))}
                </select>
              </div>

              <div className="subsection">
                <h3>New key</h3>
                <div className="checks">
                  {ALL_PERMISSIONS.map((p) => (
                    <label key={p}>
                      <input
                        type="checkbox"
                        checked={newKeyPermissions.includes(p)}
                        onChange={(e) =>
                          setNewKeyPermissions((current) =>
                            e.target.checked ? [...current, p] : current.filter((x) => x !== p),
                          )
                        }
                      />
                      {p}
                    </label>
                  ))}
                </div>
                <button onClick={issueKey} disabled={busy || newKeyPermissions.length === 0}>
                  Issue key
                </button>
              </div>

              <div className="subsection actions">
                <button onClick={reset} disabled={busy}>
                  Reset sandbox
                </button>
                <span className="field-row">
                  <input
                    className="hold-input"
                    inputMode="numeric"
                    placeholder="Hold id"
                    value={holdId}
                    onChange={(e) => setHoldId(e.target.value.replace(/\D/g, ""))}
                  />
                  <button onClick={expire} disabled={busy || holdId === ""}>
                    Expire hold
                  </button>
                </span>
              </div>
            </section>

            <section className="card">
              <div className="tabs" role="tablist">
                <button role="tab" aria-selected={tab === "mcp"} className={tab === "mcp" ? "tab active" : "tab"} onClick={() => setTab("mcp")}>
                  Connect an agent (MCP)
                </button>
                <button role="tab" aria-selected={tab === "curl"} className={tab === "curl" ? "tab active" : "tab"} onClick={() => setTab("curl")}>
                  curl quickstart
                </button>
              </div>
              {tab === "mcp" ? (
                <CopyBlock label="MCP config" text={mcpConfig(__API_URL__, __MCP_ENTRY__, apiKey, customerId)} />
              ) : (
                <CopyBlock label="curl" text={curlQuickstart(__API_URL__, apiKey, example && customerId ? { ...example, customerId } : example)} />
              )}
            </section>
          </div>

          <section className="card">
            <h2>
              Recent requests <span className="muted">every 2 s, newest first</span>
            </h2>
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Method</th>
                  <th>Path</th>
                  <th>Status</th>
                  <th>Code</th>
                  <th>Replayed</th>
                  <th>Client</th>
                </tr>
              </thead>
              <tbody>
                {requests.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="muted">
                      No /v1 requests yet.
                    </td>
                  </tr>
                ) : (
                  requests.map((r) => (
                    <tr key={r.id}>
                      <td className="mono">{new Date(r.created_at).toLocaleTimeString()}</td>
                      <td className="mono">{r.method}</td>
                      <td className="mono path">{r.path}</td>
                      <td>
                        <span className={`pill s${String(r.status)[0]}`}>{r.status}</span>
                      </td>
                      <td className="mono">{r.code ?? ""}</td>
                      <td>{r.replayed ? <span className="pill replayed">replayed</span> : ""}</td>
                      <td>{r.client ?? "other"}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </section>
        </>
      )}
    </div>
  );
}
