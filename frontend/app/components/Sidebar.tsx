"use client";

import { formatMon, type ModelInfo, type VerifierHealth } from "@/lib/api";

interface SidebarProps {
  models: ModelInfo[];
  verifier: VerifierHealth | null;
  onNewChat: () => void;
}

function StatusDot({ up }: { up: boolean | undefined }) {
  const color = up === undefined ? "bg-muted" : up ? "bg-ok" : "bg-bad";
  return (
    <span className="relative flex h-2 w-2">
      {up && <span className={`absolute inline-flex h-full w-full rounded-full ${color} opacity-60 animate-ping`} />}
      <span className={`relative inline-flex h-2 w-2 rounded-full ${color}`} />
    </span>
  );
}

function MachineRow({ name, role, up }: { name: string; role: string; up: boolean | undefined }) {
  return (
    <div className="flex items-center gap-3 rounded-xl px-3 py-2.5 bg-white/[0.02] border border-line">
      <StatusDot up={up} />
      <div className="min-w-0 flex-1">
        <div className="text-sm text-ink">{name}</div>
        <div className="text-xs text-muted truncate">{role}</div>
      </div>
      <span className={`text-[11px] font-mono ${up ? "text-ok" : up === false ? "text-bad" : "text-muted"}`}>
        {up === undefined ? "…" : up ? "online" : "offline"}
      </span>
    </div>
  );
}

const STEPS = [
  ["Sign", "You sign each prompt in your wallet. Free, no gas."],
  ["Answer", "A provider machine runs the model you picked."],
  ["Lock", "The price is locked from your deposit on Monad."],
  ["Verify", "Machine 3 re-runs it and compares the answers."],
  ["Settle", "Match: the machine is paid. Mismatch: you're refunded and it's slashed."],
];

export default function Sidebar({ models, verifier, onNewChat }: SidebarProps) {
  const byModel = Object.fromEntries(models.map((m) => [m.model, m]));
  const price = (id: string) => (byModel[id]?.price_wei ? ` · ${formatMon(byModel[id].price_wei)} MON` : "");

  return (
    <aside className="hidden lg:flex w-80 shrink-0 flex-col gap-6 border-r border-line bg-panel/60 backdrop-blur p-5 overflow-y-auto">
      <div>
        <div className="font-brand text-2xl font-bold tracking-tight">
          Infer<span className="text-violet">MON</span>
        </div>
        <p className="mt-1.5 text-sm text-muted leading-snug">Verified AI inference, paid in MON on Monad.</p>
      </div>

      <button
        onClick={onNewChat}
        className="flex items-center justify-center gap-2 rounded-xl border border-line bg-white/[0.03] px-3 py-2.5 text-sm hover:bg-white/[0.06] hover:border-violet/40 transition"
      >
        <span className="text-lg leading-none">+</span> New chat
      </button>

      <section>
        <div className="mb-2.5 flex items-center justify-between">
          <h2 className="text-[11px] uppercase tracking-[0.14em] text-muted">Network</h2>
          <span className="flex items-center gap-1.5 rounded-full border border-violet/30 bg-violet/10 px-2 py-0.5 text-[11px] text-violet-2">
            <span className="h-1.5 w-1.5 rounded-full bg-violet" /> Monad testnet
          </span>
        </div>
        <div className="flex flex-col gap-2">
          <MachineRow name="Machine 1" role={`Provider · llama 1B${price("1B")}`} up={byModel["1B"]?.online} />
          <MachineRow name="Machine 2" role={`Provider · llama 3B${price("3B")}`} up={byModel["3B"]?.online} />
          <MachineRow name="Machine 3" role="Verifier · re-runs answers" up={verifier ? verifier.verifier_machine_online : undefined} />
        </div>
      </section>

      <section>
        <h2 className="mb-2.5 text-[11px] uppercase tracking-[0.14em] text-muted">How it works</h2>
        <ol className="flex flex-col gap-3">
          {STEPS.map(([title, text], i) => (
            <li key={title} className="flex gap-3">
              <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-violet/15 text-[11px] font-mono text-violet-2">
                {i + 1}
              </span>
              <div className="text-sm leading-snug">
                <span className="text-ink">{title}</span> <span className="text-muted">{text}</span>
              </div>
            </li>
          ))}
        </ol>
      </section>
    </aside>
  );
}
