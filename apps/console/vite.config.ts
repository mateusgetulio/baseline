import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const apiUrl = process.env.BASELINE_API_URL ?? "http://localhost:3000";
const adminToken = process.env.SANDBOX_ADMIN_TOKEN ?? "";

export default defineConfig({
  plugins: [react()],
  define: {
    __API_URL__: JSON.stringify(apiUrl),
    __MCP_ENTRY__: JSON.stringify(resolve(import.meta.dirname, "../mcp/dist/src/index.js")),
  },
  server: {
    port: Number(process.env.BASELINE_CONSOLE_PORT ?? 5173),
    strictPort: true,
    proxy: {
      "/v1": { target: apiUrl, changeOrigin: true },
      "/sandbox": {
        target: apiUrl,
        changeOrigin: true,
        headers: { Authorization: `Bearer ${adminToken}` },
      },
    },
  },
});
