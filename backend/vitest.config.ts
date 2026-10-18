import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@app": path.resolve(__dirname, "app"),
      "@": path.resolve(__dirname, "src"),
    },
  },
  test: {
    environment: "node",
    globalSetup: ["./tests/global-setup.ts"],
    setupFiles: ["./tests/setup.ts"],
    pool: "forks",
    // Máy dev chậm (antivirus quét file DB tạm): giới hạn số process song song, nới timeout.
    poolOptions: { forks: { maxForks: 3, minForks: 1 } },
    testTimeout: 120000,
    hookTimeout: 120000,
  },
});
