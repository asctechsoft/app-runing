import type { NextConfig } from "next";

// Header an toàn cho toàn bộ API (N01). Route handler cũng tự gắn header này để test trực tiếp.
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "no-referrer" },
  { key: "Cache-Control", value: "no-store" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  serverExternalPackages: ["@prisma/client", "bcryptjs"],
  async headers() {
    return [{ source: "/api/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
