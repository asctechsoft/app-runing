import { AppError } from "@/lib/errors";
import { limitFeedback, limitUserLookup } from "@/lib/rate-limit";
import { redactText } from "@/lib/redact";
import { userRepository } from "@/server/repositories/auth.repository";
import { feedbackRepository } from "@/server/repositories/feedback.repository";
import { blockRepository } from "@/server/repositories/social.repository";
import { feedbackSchema, userLookupQuery } from "@/server/validators/misc";

const userNotFound = () => new AppError(404, "user_not_found", "User not found");

export const userService = {
  /**
   * Tra cứu theo email để chọn người xem live share. Chỉ trả {id, displayName}; không bao giờ trả email/PII.
   * Mọi trường hợp không đủ điều kiện (không tồn tại, chưa xác minh, không active, chặn nhau, chính mình) => cùng một 404.
   * Rate limit chạy trước khi truy vấn để mọi lần dò đều bị tính.
   */
  async lookupByEmail(callerId: string, rawQuery: unknown) {
    await limitUserLookup(callerId);
    const { email } = userLookupQuery.parse(rawQuery);
    const user = await userRepository.findByEmail(email);
    if (!user || user.status !== "active" || !user.emailVerifiedAt || user.id === callerId) throw userNotFound();
    if (await blockRepository.isBlockedEitherWay(callerId, user.id)) throw userNotFound();
    return { id: user.id, displayName: user.displayName };
  },

  /** Feedback: diagnostics đi qua redact (token, mật khẩu, tọa độ) trước khi lưu. */
  async submitFeedback(userId: string | null, ip: string, raw: unknown) {
    const input = feedbackSchema.parse(raw);
    await limitFeedback(userId ? `user:${userId}` : `ip:${ip}`);
    const row = await feedbackRepository.create({
      ownerId: userId,
      message: input.message,
      diagnostics: input.diagnostics ? redactText(input.diagnostics) : null,
      appVersion: input.appVersion ?? null,
    });
    return { id: row.id };
  },
};
