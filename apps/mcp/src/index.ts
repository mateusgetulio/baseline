#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { BaselineApi } from "./api.js";
import { buildServer } from "./server.js";

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`baseline-mcp: set ${name}.`);
    process.exit(1);
  }
  return value;
}

const api = new BaselineApi(process.env.BASELINE_API_URL ?? "http://localhost:3000", required("BASELINE_API_KEY"));
const customerId = Number(required("BASELINE_CUSTOMER_ID"));
const me = await api.me();
const server = buildServer(api, me, { customerId });
await server.connect(new StdioServerTransport());
