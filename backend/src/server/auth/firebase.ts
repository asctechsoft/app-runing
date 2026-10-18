import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { AppError, unauthorized } from "@/lib/errors";

// Xác minh Firebase ID token KHÔNG cần firebase-admin/service account:
// chữ ký RS256 theo JWKS công khai của Google, iss/aud theo FIREBASE_PROJECT_ID.

export const FIREBASE_JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

export interface FirebaseClaims {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  signInProvider: string;
}

export interface FirebaseTokenVerifier {
  /** Ném 401 `invalid_id_token` nếu token không hợp lệ. */
  verify(idToken: string): Promise<FirebaseClaims>;
}

const invalid = () => unauthorized("invalid_id_token", "ID token is invalid or expired");

export class JoseFirebaseTokenVerifier implements FirebaseTokenVerifier {
  constructor(
    private readonly projectId: string,
    private readonly jwks: JWTVerifyGetKey,
    private readonly requiredProvider = "google.com",
  ) {}

  async verify(idToken: string): Promise<FirebaseClaims> {
    let payload: Record<string, unknown>;
    try {
      // jose kiểm tra chữ ký, alg, iss, aud và exp/iat.
      ({ payload } = await jwtVerify(idToken, this.jwks, {
        algorithms: ["RS256"],
        issuer: `https://securetoken.google.com/${this.projectId}`,
        audience: this.projectId,
      }));
    } catch {
      throw invalid();
    }
    const sub = payload.sub;
    if (typeof sub !== "string" || sub.length === 0 || sub.length > 128) throw invalid();
    const authTime = payload.auth_time;
    if (typeof authTime !== "number" || authTime > Math.floor(Date.now() / 1000)) throw invalid();
    const firebase = payload.firebase as { sign_in_provider?: unknown } | undefined;
    if (firebase?.sign_in_provider !== this.requiredProvider) throw invalid();
    return {
      uid: sub,
      email: typeof payload.email === "string" ? payload.email.trim().toLowerCase() : null,
      emailVerified: payload.email_verified === true,
      name: typeof payload.name === "string" && payload.name.trim() ? payload.name.trim().slice(0, 60) : null,
      signInProvider: firebase.sign_in_provider,
    };
  }
}

const g = globalThis as unknown as {
  __strideFirebaseVerifier?: FirebaseTokenVerifier | null;
  __strideGoogleJwks?: JWTVerifyGetKey;
  __strideGoogleJwksProject?: string;
  __strideDefaultVerifier?: FirebaseTokenVerifier;
};

/** Chỉ dùng trong test: thay verifier (vd. JWKS local). Truyền null để bỏ. */
export function setFirebaseVerifierForTests(v: FirebaseTokenVerifier | null) {
  g.__strideFirebaseVerifier = v;
}

/** Verifier hiện hành; ném 503 nếu chưa cấu hình FIREBASE_PROJECT_ID. */
export function firebaseVerifier(): FirebaseTokenVerifier {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId) throw new AppError(503, "provider_not_configured", "Google sign-in is not configured");
  if (g.__strideFirebaseVerifier) return g.__strideFirebaseVerifier;
  if (!g.__strideDefaultVerifier || g.__strideGoogleJwksProject !== projectId) {
    // createRemoteJWKSet tự cache khóa theo Cache-Control và tải lại khi gặp kid lạ.
    g.__strideGoogleJwks ??= createRemoteJWKSet(new URL(FIREBASE_JWKS_URL));
    g.__strideDefaultVerifier = new JoseFirebaseTokenVerifier(projectId, g.__strideGoogleJwks);
    g.__strideGoogleJwksProject = projectId;
  }
  return g.__strideDefaultVerifier;
}
