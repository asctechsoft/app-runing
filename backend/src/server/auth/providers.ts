// Interface cho đăng nhập bằng provider ngoài (E02).
// - Google: đã hiện thực qua Firebase Auth (src/server/auth/firebase.ts, route POST /auth/firebase).
// - Apple: CHƯA có cấu hình nên KHÔNG có route; registry rỗng. Khi có: hiện thực provider, đăng ký vào đây, rồi mới thêm route.

export type ExternalProviderId = "apple" | "google";

export interface ExternalIdentity {
  provider: ExternalProviderId;
  subject: string;
  email: string | null;
  emailVerified: boolean;
}

export interface ExternalIdentityProvider {
  readonly id: ExternalProviderId;
  /** Xác minh id token do SDK phía mobile trả về (chữ ký, audience, hạn). */
  verifyIdToken(idToken: string, nonce?: string): Promise<ExternalIdentity>;
}

const registry = new Map<ExternalProviderId, ExternalIdentityProvider>();

export function getExternalProvider(id: ExternalProviderId): ExternalIdentityProvider | null {
  return registry.get(id) ?? null;
}
