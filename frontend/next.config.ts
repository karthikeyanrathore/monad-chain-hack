import type { NextConfig } from "next";

// The Inference Service (backend/inference-service). Proxied under /backend so the browser
// talks to the same origin and no CORS setup is needed.
const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:8000";
// The Verification Service (backend/verification-service), proxied under /verifier.
const VERIFIER_URL = process.env.VERIFIER_URL ?? "http://localhost:9000";

const nextConfig: NextConfig = {
  rewrites: async () => [
    { source: "/backend/:path*", destination: `${BACKEND_URL}/:path*` },
    { source: "/verifier/:path*", destination: `${VERIFIER_URL}/:path*` },
  ],
  experimental: {
    // /infer waits for the model and the on-chain recordRequest; the default proxy timeout is 30 s.
    proxyTimeout: 180_000,
  },
};

export default nextConfig;
