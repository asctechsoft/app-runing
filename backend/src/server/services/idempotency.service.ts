import { sha256Hex } from "@/lib/crypto";
import { badRequest, unprocessable } from "@/lib/errors";
import { isUniqueViolation } from "@/lib/prisma";
import { idempotencyRepository } from "@/server/repositories/idempotency.repository";

// C06: Idempotency-Key cho endpoint thay đổi dữ liệu. Lưu key + hash request + response theo từng user.
// Cùng key + cùng request -> trả lại response cũ. Cùng key + request khác -> 422.

const KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

export interface IdempotentCall {
  userId: string;
  key: string;
  method: string;
  path: string;
  body: string;
}

function replay(statusCode: number, body: string): Response {
  return new Response(statusCode === 204 ? null : body, {
    status: statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Idempotent-Replayed": "true",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    },
  });
}

export const idempotencyService = {
  requestHash(method: string, path: string, body: string) {
    return sha256Hex(`${method.toUpperCase()} ${path}\n${body}`);
  },

  /** Lưu kết quả của một thao tác idempotent (cũng dùng cho từng operation trong sync push). */
  async lookup(userId: string, key: string, requestHash: string) {
    const existing = await idempotencyRepository.find(userId, key);
    if (!existing) return null;
    if (existing.requestHash !== requestHash) {
      throw unprocessable("idempotency_key_reused", "Idempotency-Key was already used with a different request");
    }
    return existing;
  },

  async store(call: Omit<IdempotentCall, "body"> & { requestHash: string }, statusCode: number, body: string) {
    try {
      await idempotencyRepository.create({
        userId: call.userId,
        key: call.key,
        method: call.method,
        path: call.path,
        requestHash: call.requestHash,
        statusCode,
        responseBody: body,
        responseHash: sha256Hex(body),
      });
    } catch (err) {
      // Request song song cùng key: bản ghi đầu tiên thắng.
      if (!isUniqueViolation(err)) throw err;
    }
  },

  async run(call: IdempotentCall, exec: () => Promise<Response>): Promise<Response> {
    if (!KEY_RE.test(call.key)) throw badRequest("invalid_idempotency_key", "Idempotency-Key must be 8-128 chars [A-Za-z0-9_-:.]");
    const requestHash = this.requestHash(call.method, call.path, call.body);
    const existing = await this.lookup(call.userId, call.key, requestHash);
    if (existing) return replay(existing.statusCode, existing.responseBody);

    const res = await exec();
    // Chỉ lưu kết quả xác định (2xx/4xx); lỗi 5xx và 429 để client thử lại.
    if (res.status < 500 && res.status !== 429) {
      const text = await res.clone().text();
      await this.store({ ...call, requestHash }, res.status, text);
    }
    return res;
  },
};
