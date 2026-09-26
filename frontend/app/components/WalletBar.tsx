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
  const [amount, setAmount] = useState("0.1");
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

  if (!address) {
    return (
      <div className="flex items-center gap-3">
        {status?.error && <span className="text-xs text-red-400 max-w-xs truncate">{status.text}</span>}
        {USER_ADDRESS && (
          <span className="font-mono text-xs text-gray-400 select-all" title="Only this wallet can connect">
            user {USER_ADDRESS}
          </span>
        )}
        <button
          onClick={() => run("connect", async () => setAddress(await connect()))}
          disabled={busy !== null}
          className="rounded-lg bg-orange-600 hover:bg-orange-500 disabled:opacity-50 px-3 py-1.5 text-sm font-medium transition"
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
    <div className="flex flex-wrap items-center justify-end gap-3 text-sm">
      {status && (
        <span className={`text-xs max-w-xs truncate ${status.error ? "text-red-400" : "text-green-400"}`}>
          {status.href ? (
            <a href={status.href} target="_blank" rel="noreferrer" className="underline">
              {status.text}
            </a>
          ) : (
            status.text
          )}
        </span>
      )}
      <div className="text-gray-300">
        Deposit <span className="font-semibold text-gray-100">{formatMon(account?.deposited_wei)} MON</span>
      </div>
      <input
        id="amount"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        inputMode="decimal"
        aria-label="Amount in MON"
        className="w-20 rounded-lg bg-[#2a2a2a] border border-white/10 px-2 py-1.5 text-right outline-none focus:border-orange-500/50"
      />
      <button
        onClick={() => move("deposit")}
        disabled={busy !== null}
        className="rounded-lg bg-orange-600 hover:bg-orange-500 disabled:opacity-50 px-3 py-1.5 font-medium transition"
      >
        {busy === "deposit" ? "Depositing…" : "Deposit"}
      </button>
      <button
        onClick={() => move("withdraw")}
        disabled={busy !== null}
        className="rounded-lg border border-white/10 hover:bg-white/5 disabled:opacity-50 px-3 py-1.5 transition"
      >
        {busy === "withdraw" ? "Withdrawing…" : "Withdraw"}
      </button>
      <span className="rounded-lg bg-[#2a2a2a] px-2.5 py-1.5 font-mono text-xs text-gray-300 select-all">
        {address}
      </span>
    </div>
  );
}
