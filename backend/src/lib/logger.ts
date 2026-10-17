import { redact } from "./redact";

// Logger duy nhất của backend; mọi payload đều đi qua redact().
type Level = "info" | "warn" | "error";

function write(level: Level, msg: string, meta?: unknown) {
  if (process.env.LOG_SILENT === "1") return;
  const line = JSON.stringify({ level, msg, time: new Date().toISOString(), meta: meta === undefined ? undefined : redact(meta) });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.info(line);
}

export const logger = {
  info: (msg: string, meta?: unknown) => write("info", msg, meta),
  warn: (msg: string, meta?: unknown) => write("warn", msg, meta),
  error: (msg: string, meta?: unknown) => write("error", msg, meta),
};
