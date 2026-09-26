"use client";

import { useState } from "react";
import { depositTx, withdrawTx, formatMon, type Account } from "@/lib/api";
import { connect, sendAndWait, explorerTx, USER_ADDRESS } from "@/lib/wallet";

interface WalletBarProps {
  address: string | null;
  setAddress: (a: string | null) => void;
  account: Account | null;
  refresh: () => Promise<void>;
}

export default function WalletBar({ address, setAddress, account, refresh }: WalletBarProps) {
  const [amount, setAmount] = useState("0.5");
  const [busy, setBusy] = useState<string | null>(null);
  const [status, setStatus] = useState<{ text: string; href?: string; error?: boolean } | null>(null);

  const run = async (label: string, fn: () => Promise<{ text: string; href?: string } | void>) => {
    setBusy(label);
    setStatus(null);
    try {
      const result = await fn();
      if (result) setStatus(result);
    } catch (e) {
      setStatus({ text: (e as Error).message, error: true });
    } finally {
      setBusy(null);
    }
  };

  const statusLine = status && (
    <span className={`text-xs max-w-xs truncate ${status.error ? "text-bad" : "text-ok"}`} title={status.text}>
      {status.href ? (
        <a href={status.href} target="_blank" rel="noreferrer" className="underline underline-offset-2">
          {status.text} ↗
        </a>
      ) : (
        status.text
      )}
    </span>
  );

  if (!address) {
    return (
      <div className="flex items-center gap-3">
        {statusLine}
        {USER_ADDRESS && <span className="hidden md:inline font-mono text-xs text-muted select-all">{USER_ADDRESS}</span>}
        <button
          onClick={() => run("connect", async () => setAddress(await connect()))}
          disabled={busy !== null}
          className="rounded-xl bg-gradient-to-br from-violet to-[#5b45e0] px-4 py-2 text-sm font-medium text-white shadow-[0_8px_24px_-8px_rgba(131,110,249,0.9)] transition hover:brightness-110 disabled:opacity-50"
        >
          {busy ? "Connecting…" : "Connect wallet"}
        </button>
      </div>
    );
  }

  const move = (kind: "deposit" | "withdraw") =>
    run(kind, async () => {
      const tx = kind === "deposit" ? await depositTx(address, amount) : await withdrawTx(address, amount);
      const hash = await sendAndWait(tx);
      await refresh();
      return { text: `${kind === "deposit" ? "Deposited" : "Withdrew"} ${amount} MON`, href: explorerTx(hash) };
    });

  return (
    <div className="flex flex-wrap items-center justify-end gap-2.5">
      {statusLine}

      {/* Deposit balance: what prompts are paid from */}
      <div className="flex items-center gap-2 rounded-xl border border-line bg-panel/80 pl-3 pr-1 py-1">
        <div className="leading-tight">
          <div className="text-[10px] uppercase tracking-[0.12em] text-muted">Deposit</div>
          <div className="font-mono text-sm text-ink">{formatMon(account?.deposited_wei)} MON</div>
        </div>
        <div className="flex items-center gap-1 rounded-lg bg-black/30 p-1">
          <input
            id="amount"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            inputMode="decimal"
            aria-label="Amount in MON"
            className="w-14 bg-transparent px-1.5 text-right font-mono text-sm text-ink outline-none"
          />
          <button
            onClick={() => move("deposit")}
            disabled={busy !== null}
            className="rounded-md bg-violet px-2.5 py-1 text-xs font-medium text-white transition hover:brightness-110 disabled:opacity-50"
          >
            {busy === "deposit" ? "…" : "Deposit"}
          </button>
          <button
            onClick={() => move("withdraw")}
            disabled={busy !== null}
            className="rounded-md px-2.5 py-1 text-xs text-muted transition hover:text-ink hover:bg-white/5 disabled:opacity-50"
          >
            {busy === "withdraw" ? "…" : "Withdraw"}
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 rounded-xl border border-line bg-panel/80 px-3 py-2">
        <span className="h-2 w-2 rounded-full bg-ok" />
        <span className="font-mono text-xs text-ink/90 select-all">{address}</span>
      </div>
    </div>
  );
}
