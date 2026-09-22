/// <reference types="vitest/config" />
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";

// The API host is injected by compose (http://api:3000). Falling back to
// localhost keeps `npm run dev` working outside a container.
const apiTarget = process.env.VITE_API_PROXY_TARGET ?? "http://localhost:3000";

export default defineConfig({
  plugins: [react()],

  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },

  server: {
    host: "0.0.0.0",
    port: 5173,
    // Vite rejects requests whose Host header it does not recognise, which
    // is a DNS-rebinding protection worth keeping. Inside compose the
    // service is reached as "web" by other containers, so that name has to
    // be allowed or those requests get a 403 with an empty page.
    allowedHosts: ["localhost", "web", "127.0.0.1"],
    // The proxy runs server-side, so the browser only ever talks to
    // localhost:5173. Same origin means no CORS and no SameSite cookie
    // handling — the single-deployment decision, applied to development.
    proxy: {
      "/api": {
        target: apiTarget,
        changeOrigin: false,
      },
    },
    // File events do not always cross the container boundary reliably on
    // macOS. Polling costs a little CPU and buys hot reload that works.
    watch: { usePolling: true, interval: 300 },
  },

  build: {
    // Rails serves the built bundle from its own public directory: one
    // process, one URL, no second host and no CORS configuration.
    outDir: "../api/public",
    // Rails keeps robots.txt and its error pages here. Emptying the
    // directory on build would delete them.
    emptyOutDir: false,
    sourcemap: true,
  },

  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    css: false,
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      exclude: ["src/test/**", "**/*.d.ts", "src/main.tsx"],
    },
  },
});
