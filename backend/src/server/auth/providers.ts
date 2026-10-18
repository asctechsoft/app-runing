// Interface cho đăng nhập Apple/Google (E02). CHƯA có client ID nên KHÔNG có route nào dùng tới;
// registry rỗng. Khi có cấu hình: hiện thực provider, đăng ký vào đây, rồi mới thêm route.

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
