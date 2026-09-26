// Calls to the Inference Service and Verification Service.
// Deployed (e.g. Vercel): set NEXT_PUBLIC_BACKEND_URL / NEXT_PUBLIC_VERIFIER_URL to their public URLs; the
// browser calls them directly (both services allow CORS), so there is no proxy timeout on slow answers.
// Local dev: leave them unset; next.config.ts proxies /backend and /verifier to localhost.
const BACKEND = process.env.NEXT_PUBLIC_BACKEND_URL || "/backend";
const VERIFIER = process.env.NEXT_PUBLIC_VERIFIER_URL || "/verifier";

export interface ModelInfo {
  model: string;
  provider: string;
  configured: boolean;
  price_wei?: string;
}

export interface Account {
  address: string;
  deposited_wei: string;
  wallet_wei: string;
  stake_wei: string;
}

export interface InferResult {
  request_id: string;
  model: string;
  provider: string;
  answer: string;
  user: string | null;
  tx_hash: string | null;
}

/** Unsigned transaction built by the backend; hex quantities, ready for eth_sendTransaction. */
export type UnsignedTx = Record<string, string>;

export interface Verdict {
  request_id: string;
  sampled: boolean;
  status: "pending" | "not_sampled" | "done" | "skipped" | "error";
  passed?: boolean;
  similarity?: number;
  tx_hash?: string;
  reason?: string;
}

async function call<T>(path: string, init?: RequestInit, base = BACKEND): Promise<T> {
  const res = await fetch(`${base}${path}`, {
    ...init,
    headers: { "content-type": "application/json", ...init?.headers },
  }).catch(() => {
    throw new Error("The InferMON backend is not reachable right now. Please try again shortly.");
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    if (!body) throw new Error("The InferMON backend is not reachable right now. Please try again shortly.");
    const detail = typeof body.detail === "string" ? body.detail : JSON.stringify(body.detail ?? body);
    throw new Error(detail);
  }
  return body as T;
}

export const getModels = () => call<ModelInfo[]>("/models");
export const getAccount = (address: string) => call<Account>(`/account/${address}`);
export const depositTx = (address: string, amount: string) =>
  call<UnsignedTx>("/tx/deposit", { method: "POST", body: JSON.stringify({ address, amount }) });
export const withdrawTx = (address: string, amount: string) =>
  call<UnsignedTx>("/tx/withdraw", { method: "POST", body: JSON.stringify({ address, amount }) });
export const getVerdict = (requestId: string) => call<Verdict>(`/verdicts/${requestId}`, undefined, VERIFIER);
export const infer = (body: { model: string; prompt: string; nonce: number; signature: string }) =>
  call<InferResult>("/infer", { method: "POST", body: JSON.stringify(body) });

/** The exact text the backend expects the user to sign for one paid request. */
export const requestMessage = (model: string, nonce: number, prompt: string) =>
  `InferenceTruth request\nmodel: ${model}\nnonce: ${nonce}\nprompt: ${prompt}`;

/** Wei (decimal string) to a short MON string. */
export function formatMon(wei: string | undefined, digits = 4): string {
  if (!wei) return "–";
  const v = BigInt(wei);
  const whole = v / 10n ** 18n;
  const frac = (v % 10n ** 18n).toString().padStart(18, "0").slice(0, digits).replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : whole.toString();
}
