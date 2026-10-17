import { isProduction } from "@/lib/env";
import { logger } from "@/lib/logger";
import { maskEmail } from "@/lib/redact";

export interface MailMessage {
  to: string;
  subject: string;
  text: string;
  /** Link hành động (xác minh, đặt lại mật khẩu). Chỉ in ra console ở dev. */
  actionUrl?: string;
}

export interface Mailer {
  send(message: MailMessage): Promise<void>;
}

/** Dev: in link ra console. Production: không bao giờ in token/link, chỉ cảnh báo thiếu driver thật. */
export class ConsoleMailer implements Mailer {
  async send(message: MailMessage): Promise<void> {
    if (isProduction()) {
      logger.warn("ConsoleMailer used in production; email not delivered", {
        to: maskEmail(message.to),
        subject: message.subject,
      });
      return;
    }
    // Chỉ dev: in link để người phát triển bấm thử (không qua logger vì redact sẽ che token).
    console.info(`[dev-mail] to=${message.to} subject="${message.subject}" link=${message.actionUrl ?? "-"}`);
  }
}

/** Test: giữ thư trong bộ nhớ. */
export class MemoryMailer implements Mailer {
  readonly outbox: MailMessage[] = [];
  async send(message: MailMessage): Promise<void> {
    this.outbox.push(message);
  }
}

const g = globalThis as unknown as { __strideMemoryMailer?: MemoryMailer };

export function memoryMailer(): MemoryMailer {
  g.__strideMemoryMailer ??= new MemoryMailer();
  return g.__strideMemoryMailer;
}

export function mailer(): Mailer {
  const kind = process.env.MAILER_DRIVER ?? "console";
  if (kind === "memory") {
    if (isProduction()) throw new Error("Memory mailer is not allowed in production");
    return memoryMailer();
  }
  return new ConsoleMailer();
}
