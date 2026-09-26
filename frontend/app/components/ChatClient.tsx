"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import PromptBox from "./PromptBox";
import WalletBar from "./WalletBar";
import Sidebar from "./Sidebar";
import ProofTrail, { type Proof } from "./ProofTrail";
import { MODELS, type Model } from "@/lib/models";
import {
  getAccount,
  getModels,
  getMachines,
  getVerdict,
  getVerifierHealth,
  infer,
  requestMessage,
  type Account,
  type ModelInfo,
  type VerifierHealth,
} from "@/lib/api";
import { signMessage, onAccountsChanged, isAllowed, notAllowedMessage } from "@/lib/wallet";

interface Message {
  role: "user" | "assistant";
  text: string;
  error?: boolean;
  proof?: Proof;
}

const SUGGESTIONS = [
  "Explain Monad's parallel execution in two sentences.",
  "Write a haiku about decentralized AI.",
  "What is Newton's third law?",
  "Give me three startup ideas for a hackathon.",
];

export default function ChatClient() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [model, setModel] = useState<Model>(MODELS[0]);
  const [stage, setStage] = useState<null | "sign" | "answer">(null);
  const [address, setAddress] = useState<string | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [machines, setMachines] = useState<Record<string, boolean> | null>(null);
  const [verifier, setVerifier] = useState<VerifierHealth | null | "down">(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  const prices = Object.fromEntries(models.map((m) => [m.model, m.price_wei ?? ""]));

  const refresh = useCallback(async () => {
    if (address) setAccount(await getAccount(address));
  }, [address]);

  // Prices + live machine status, refreshed every 15 s for the sidebar.
  useEffect(() => {
    const load = () => {
      getModels().then(setModels).catch(() => setModels([]));
      getMachines().then(setMachines).catch(() => setMachines({}));
      getVerifierHealth().then(setVerifier).catch(() => setVerifier("down"));
    };
    load();
    const t = setInterval(load, 15_000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    refresh().catch(() => setAccount(null));
  }, [refresh]);

  // Follow the wallet's selected account (each account has its own deposit).
  useEffect(
    () =>
      onAccountsChanged((next) => {
        if (isAllowed(next)) {
          setAddress(next);
          return;
        }
        setAddress(null);
        setAccount(null);
        if (next) {
          setMessages((prev) => [...prev, { role: "assistant", text: notAllowedMessage(next), error: true }]);
        }
      }),
    [],
  );

  // Poll the Verification Service until the request's verdict is final.
  const watchVerdict = useCallback(
    async (requestId: string) => {
      for (let i = 0; i < 360; i++) {
        await new Promise((r) => setTimeout(r, 2000));
        const verdict = await getVerdict(requestId).catch(() => null);
        if (!verdict) continue;
        setMessages((prev) =>
          prev.map((m) => (m.proof?.requestId === requestId ? { ...m, proof: { ...m.proof, verdict } } : m)),
        );
        if (verdict.status !== "pending") {
          await refresh();
          return;
        }
      }
    },
    [refresh],
  );

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, stage]);

  const send = async (text: string) => {
    if (!text.trim() || stage) return;
    setMessages((prev) => [...prev, { role: "user", text }]);
    setInput("");

    try {
      if (!address) throw new Error("Connect your wallet first (top right), then deposit some MON.");
      // One nonce per request: the signature authorizes exactly one paid prompt.
      const nonce = Date.now();
      setStage("sign");
      const signature = await signMessage(address, requestMessage(model.id, nonce, text));
      setStage("answer");
      const res = await infer({ model: model.id, prompt: text, nonce, signature });
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: res.answer,
          proof: {
            model: model.name,
            provider: res.provider,
            charged: prices[model.id],
            txHash: res.tx_hash,
            requestId: res.request_id,
            verdict: null,
          },
        },
      ]);
      await refresh();
      void watchVerdict(res.request_id);
    } catch (e) {
      setMessages((prev) => [...prev, { role: "assistant", text: (e as Error).message, error: true }]);
    } finally {
      setStage(null);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send(input);
    }
  };

  const isEmpty = messages.length === 0;
  const machine = model.id === "1B" ? "Machine 1" : "Machine 2";
  const promptBox = (centered: boolean) => (
    <PromptBox
      input={input}
      setInput={setInput}
      onSend={() => void send(input)}
      onKeyDown={handleKeyDown}
      model={model}
      setModel={setModel}
      prices={prices}
      centered={centered}
      disabled={stage !== null}
    />
  );

  return (
    <div className="flex h-screen text-ink">
      <Sidebar models={models} machines={machines} verifier={verifier} onNewChat={() => setMessages([])} />

      <main className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-4 border-b border-line bg-bg/60 px-5 py-3 backdrop-blur">
          <div className="font-brand text-lg font-bold tracking-tight lg:invisible">
            Infer<span className="text-violet">MON</span>
          </div>
          <WalletBar address={address} setAddress={setAddress} account={account} refresh={refresh} />
        </header>

        <div className="flex-1 overflow-y-auto">
          {isEmpty ? (
            <div className="flex min-h-full flex-col items-center justify-center px-4 py-10">
              <div className="mb-5 rounded-full border border-violet/30 bg-violet/10 px-3 py-1 text-xs text-violet-2">
                Every answer re-checked by an independent machine
              </div>
              <h1 className="font-brand text-center text-4xl font-bold leading-tight tracking-tight md:text-5xl text-balance">
                Verified AI,
                <br />
                <span className="bg-gradient-to-r from-violet-2 via-violet to-[#5b45e0] bg-clip-text text-transparent">
                  paid in MON.
                </span>
              </h1>
              <p className="mt-4 max-w-xl text-center text-muted text-balance">
                Pick a model and ask. Honest machines get paid on Monad. A machine caught cheating is slashed,
                and you get your MON back.
              </p>
              <div className="mt-8 w-full flex justify-center">{promptBox(true)}</div>
              <div className="mt-4 flex max-w-2xl flex-wrap justify-center gap-2">
                {SUGGESTIONS.map((s) => (
                  <button
                    key={s}
                    onClick={() => void send(s)}
                    className="rounded-full border border-line bg-white/[0.02] px-3 py-1.5 text-xs text-muted transition hover:border-violet/40 hover:text-ink"
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="mx-auto max-w-3xl space-y-6 px-4 py-8">
              {messages.map((m, i) =>
                m.role === "user" ? (
                  <div key={i} className="fade-up flex justify-end">
                    <div className="max-w-[80%] rounded-2xl rounded-br-md bg-gradient-to-br from-violet to-[#5b45e0] px-4 py-2.5 text-[15px] leading-relaxed text-white whitespace-pre-wrap shadow-[0_10px_30px_-12px_rgba(131,110,249,0.8)]">
                      {m.text}
                    </div>
                  </div>
                ) : (
                  <div key={i} className="fade-up flex gap-3">
                    <div className={`mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl text-xs font-bold ${m.error ? "bg-bad/15 text-bad" : "bg-violet/15 text-violet-2"}`}>
                      {m.error ? "!" : "AI"}
                    </div>
                    <div
                      className={`min-w-0 max-w-[85%] rounded-2xl rounded-tl-md border px-4 py-3 text-[15px] leading-relaxed whitespace-pre-wrap ${
                        m.error ? "border-bad/30 bg-bad/10 text-bad" : "border-line bg-panel/80 text-ink"
                      }`}
                    >
                      {m.text}
                      {m.proof && <ProofTrail proof={m.proof} />}
                    </div>
                  </div>
                ),
              )}
              {stage && (
                <div className="fade-up flex gap-3">
                  <div className="mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-violet/15 text-xs font-bold text-violet-2">
                    AI
                  </div>
                  <div className="flex items-center gap-2 rounded-2xl rounded-tl-md border border-line bg-panel/80 px-4 py-3 text-sm text-muted">
                    <span className="dot-blink flex gap-0.5 text-violet-2">
                      <span>•</span>
                      <span>•</span>
                      <span>•</span>
                    </span>
                    {stage === "sign"
                      ? "Sign the request in your wallet (free)"
                      : `${machine} is answering with ${model.name}, then it's recorded on Monad`}
                  </div>
                </div>
              )}
              <div ref={bottomRef} />
            </div>
          )}
        </div>

        {!isEmpty && <div className="px-4 pb-6 pt-2">{promptBox(false)}</div>}
      </main>
    </div>
  );
}
