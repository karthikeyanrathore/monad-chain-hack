"use client";

import { formatMon, type Verdict } from "@/lib/api";
import { explorerTx } from "@/lib/wallet";

export interface Proof {
  model: string; // display name, e.g. "llama 1B"
  provider: string; // e.g. "machine-1"
  charged?: string; // wei
  txHash?: string | null;
  requestId?: string;
  verdict?: Verdict | null;
}

type State = "done" | "active" | "bad" | "idle";

const machineName = (provider: string) => provider.replace("machine-", "Machine ");

function Step({ state, label, href, last }: { state: State; label: string; href?: string; last?: boolean }) {
  const icon = {
    done: <span className="text-ok">✓</span>,
    bad: <span className="text-bad">✗</span>,
    idle: <span className="text-muted">–</span>,
    active: (
      <span className="dot-blink flex gap-0.5 text-violet-2">
        <span>•</span>
        <span>•</span>
        <span>•</span>
      </span>
    ),
  }[state];
  const text = {
    done: "text-ink/90",
    bad: "text-bad",
    idle: "text-muted",
    active: "text-violet-2",
  }[state];
  return (
    <li className="relative flex items-start gap-2.5 pb-2.5 last:pb-0">
      {!last && <span className="absolute left-[7px] top-5 bottom-0 w-px bg-line" />}
      <span className="flex h-4 w-4 shrink-0 items-center justify-center text-[12px] leading-none mt-0.5">{icon}</span>
      {href ? (
        <a href={href} target="_blank" rel="noreferrer" className={`text-[13px] ${text} underline decoration-white/20 underline-offset-2 hover:decoration-violet`}>
          {label} ↗
        </a>
      ) : (
        <span className={`text-[13px] ${text}`}>{label}</span>
      )}
    </li>
  );
}

/** The on-chain story of one answer: signed → answered → locked → verified → paid. */
export default function ProofTrail({ proof }: { proof: Proof }) {
  const machine = machineName(proof.provider);
  const v = proof.verdict;
  const price = proof.charged ? `${formatMon(proof.charged)} MON` : "the price";
  const payout = proof.charged ? `${formatMon((BigInt(proof.charged) * 9n / 10n).toString())} MON` : "";

  let verify: { state: State; label: string; href?: string };
  let settle: { state: State; label: string; href?: string } | null = null;
  if (!v || v.status === "pending") {
    verify = { state: "active", label: v?.reason ? "Machine 3 is reconnecting, retrying…" : "Machine 3 is re-running the prompt…" };
  } else if (v.status === "done" && v.passed) {
    verify = { state: "done", label: `Verified by Machine 3 · ${Math.round((v.similarity ?? 1) * 100)}% match` };
    settle = { state: "done", label: `${machine} paid ${payout}`, href: v.tx_hash ? explorerTx(v.tx_hash) : undefined };
  } else if (v.status === "done") {
    verify = { state: "bad", label: `Mismatch on Machine 3 · ${Math.round((v.similarity ?? 0) * 100)}% match` };
    settle = { state: "bad", label: `Refunded ${price} · ${machine} slashed`, href: v.tx_hash ? explorerTx(v.tx_hash) : undefined };
  } else if (v.status === "not_sampled") {
    verify = { state: "idle", label: "Not sampled for verification" };
    settle = { state: "idle", label: `${machine} is paid after the 10-minute window` };
  } else {
    verify = { state: "idle", label: "Verification unavailable right now" };
  }

  const steps = [
    { state: "done" as State, label: "Signed by your wallet" },
    { state: "done" as State, label: `Answered by ${machine} · ${proof.model}` },
    { state: "done" as State, label: `${price} locked on Monad`, href: proof.txHash ? explorerTx(proof.txHash) : undefined },
    verify,
    ...(settle ? [settle] : []),
  ];

  return (
    <ol className="mt-3 rounded-xl border border-line bg-black/20 px-3.5 py-3">
      {steps.map((s, i) => (
        <Step key={i} {...s} last={i === steps.length - 1} />
      ))}
    </ol>
  );
}
