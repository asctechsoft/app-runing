import { AppError, unauthorized } from "@/lib/errors";
import { sessionRepository } from "@/server/repositories/auth.repository";
import { verifyAccessToken } from "./tokens";

export type AuthMode = "none" | "optional" | "user" | "userAllowDeleting";

export interface AuthUser {
  userId: string;
  sessionId: string;
  reauthAt: Date | null;
  emailVerified: boolean;
}

/**
 * Xác thực Bearer access token. Kiểm tra session chưa bị thu hồi (logout/đổi mật khẩu có hiệu lực ngay)
 * và trạng thái tài khoản.
 */
export async function authenticate(req: Request, mode: AuthMode): Promise<AuthUser | null> {
  if (mode === "none") return null;
  const header = req.headers.get("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7).trim() : null;
  if (!token) {
    if (mode === "optional") return null;
    throw unauthorized();
  }
  const claims = await verifyAccessToken(token);
  if (!claims) throw unauthorized("invalid_token", "Access token is invalid or expired");

  const session = await sessionRepository.findWithUser(claims.sessionId);
  if (!session || session.userId !== claims.userId || session.revokedAt) {
    throw unauthorized("invalid_token", "Session is no longer valid");
  }
  const user = session.user;
  if (user.status === "deleted") throw unauthorized("account_deleted", "Account has been deleted");
  if (user.status === "deleting" && mode !== "userAllowDeleting") {
    throw new AppError(403, "account_deletion_pending", "Account deletion is in progress");
  }
  return {
    userId: user.id,
    sessionId: session.id,
    reauthAt: session.reauthAt,
    emailVerified: user.emailVerifiedAt !== null,
  };
}
