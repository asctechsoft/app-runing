// Lỗi nghiệp vụ có mã ổn định; được map sang error envelope {error:{code,message,details?}} (C06).
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export const notFound = (what = "Resource") => new AppError(404, "not_found", `${what} not found`);
export const unauthorized = (code = "unauthorized", message = "Authentication required") =>
  new AppError(401, code, message);
export const forbidden = (code = "forbidden", message = "Not allowed") => new AppError(403, code, message);
export const conflict = (code: string, message: string, details?: unknown) =>
  new AppError(409, code, message, details);
export const badRequest = (code: string, message: string, details?: unknown) =>
  new AppError(400, code, message, details);
export const unprocessable = (code: string, message: string, details?: unknown) =>
  new AppError(422, code, message, details);
export const gone = (code: string, message: string) => new AppError(410, code, message);
export const tooManyRequests = (retryAfterSec: number) =>
  new AppError(429, "rate_limited", "Too many requests", { retryAfterSec });
export const payloadTooLarge = (limitBytes: number) =>
  new AppError(413, "payload_too_large", "Payload too large", { limitBytes });
