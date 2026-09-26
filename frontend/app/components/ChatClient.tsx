"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import PromptBox from "./PromptBox";
import WalletBar from "./WalletBar";
import { MODELS, type Model } from "@/lib/models";
import { getAccount, getModels, getVerdict, infer, requestMessage, formatMon, type Account, type Verdict } from "@/lib/api";
import { signMessage, explorerTx, onAccountsChanged, isAllowed, notAllowedMessage } from "@/lib/wallet";

interface Message {
  role: "user" | "assistant";
  text: string;
  error?: boolean;
  meta?: {
    model: string;
    provider: string;
    charged?: string;
    txHash?: string | null;
    requestId?: string;
    verdict?: Verdict | null;
  };
}

export default function ChatClient() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [model, setModel] = useState<Model>(MODELS[0]);
  const [loading, setLoading] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [prices, setPrices] = useState<Record<string, string>>({});
  const bottomRef = useRef<HTMLDivElement>(null);

  const refresh = useCallback(async () => {
    if (address) setAccount(await getAccount(address));
  }, [address]);

  useEffect(() => {
    getModels()
      .then((ms) => setPrices(Object.fromEntries(ms.map((m) => [m.model, m.price_wei ?? ""]))))
      .catch(() => setPrices({}));
  }, []);

  useEffect(() => {
    refresh().catch(() => setAccount(null));
  }, [refresh]);

  // If MetaMask switches to a different account, disconnect unless it is the allowed user wallet.
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
      for (let i = 0; i < 60; i++) {
        await new Promise((r) => setTimeout(r, 2000));
        const verdict = await getVerdict(requestId).catch(() => null);
        if (!verdict) continue;
        setMessages((prev) =>
          prev.map((m) => (m.meta?.requestId === requestId ? { ...m, meta: { ...m.meta, verdict } } : m)),
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
  }, [messages, loading]);

  const handleSend = async () => {
    if (!input.trim()) return;
    const prompt = input;
    setMessages((prev) => [...prev, { role: "user", text: prompt }]);
    setInput("");
    setLoading(true);

    try {
      if (!address) throw new Error("Connect your wallet first (top right).");
      // One nonce per request: the signature authorizes exactly one paid prompt.
      const nonce = Date.now();
      const signature = await signMessage(address, requestMessage(model.id, nonce, prompt));
      const res = await infer({ model: model.id, prompt, nonce, signature });
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: res.answer,
          meta: {
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
      setLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const isEmpty = messages.length === 0;

  return (
    <div className="flex h-screen bg-[#212121] text-gray-100">
      {/* Sidebar */}
      <aside className="hidden md:flex w-64 flex-col bg-[#171717] border-r border-white/10 p-3">
        <button
          onClick={() => setMessages([])}
          className="flex items-center gap-2 rounded-lg border border-white/10 px-3 py-2 text-sm hover:bg-white/5 transition"
        >
          <span className="text-lg">+</span> New chat
        </button>
        <div className="mt-6 text-xs uppercase tracking-wide text-gray-500 px-1">
          Recents
        </div>
        <div className="mt-2 flex-1 overflow-y-auto text-sm text-gray-400 space-y-1">
          <div className="px-2 py-1.5 rounded-md hover:bg-white/5 cursor-pointer truncate">
            Hackathon demo chat
          </div>
        </div>
      </aside>

      {/* Main */}
      <main className="flex-1 flex flex-col">
        {/* Top bar - ab sirf avatar/branding, model selector yahan se hata diya */}
        <header className="flex items-center justify-between gap-4 px-4 py-3 border-b border-white/10">
          <div className="text-lg font-semibold tracking-tight shrink-0">
            Infer<span className="text-orange-500">MON</span>
          </div>
          <WalletBar address={address} setAddress={setAddress} account={account} refresh={refresh} />
        </header>

        {/* Messages / empty state */}
        <div className="flex-1 overflow-y-auto">
          {isEmpty ? (
            <div className="h-full flex flex-col items-center justify-center px-4">
              <h1 className="text-3xl font-semibold text-gray-100 mb-8">
                What can I help with?
              </h1>
              <PromptBox
                input={input}
                setInput={setInput}
                onSend={handleSend}
                onKeyDown={handleKeyDown}
                model={model}
                setModel={setModel}
                prices={prices}
                centered
              />
            </div>
          ) : (
            <div className="max-w-3xl mx-auto px-4 py-6 space-y-6">
              {messages.map((m, i) => (
                <div
                  key={i}
                  className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  <div
                    className={`max-w-[80%] rounded-2xl px-4 py-2.5 text-[15px] leading-relaxed whitespace-pre-wrap ${
                      m.role === "user"
                        ? "bg-orange-600/90 text-white"
                        : m.error
                          ? "bg-red-950/60 border border-red-500/30 text-red-200"
                          : "bg-[#2a2a2a] text-gray-100"
                    }`}
                  >
                    {m.text}
                    {m.meta && (
                      <div className="mt-2 pt-2 border-t border-white/10 text-xs text-gray-400 flex flex-wrap gap-x-3">
                        <span>{m.meta.model} · {m.meta.provider}</span>
                        {m.meta.charged && <span>paid {formatMon(m.meta.charged)} MON</span>}
                        {m.meta.txHash && (
                          <a href={explorerTx(m.meta.txHash)} target="_blank" rel="noreferrer" className="underline hover:text-gray-200">
                            view on-chain
                          </a>
                        )}
                        <VerdictBadge verdict={m.meta.verdict} provider={m.meta.provider} />
                      </div>
                    )}
                  </div>
                </div>
              ))}
              {loading && (
                <div className="flex justify-start">
                  <div className="bg-[#2a2a2a] rounded-2xl px-4 py-2.5 text-gray-400 text-sm">
                    Sign in your wallet, then {model.name} answers and the payment is recorded on Monad…
                  </div>
                </div>
              )}
              <div ref={bottomRef} />
            </div>
          )}
        </div>

        {/* Bottom input (only when chat already started) */}
        {!isEmpty && (
          <div className="px-4 pb-6 pt-2">
            <PromptBox
              input={input}
              setInput={setInput}
              onSend={handleSend}
              onKeyDown={handleKeyDown}
              model={model}
              setModel={setModel}
              prices={prices}
            />
          </div>
        )}
      </main>
    </div>
  );
}
function VerdictBadge({ verdict, provider }: { verdict?: Verdict | null; provider: string }) {
  if (!verdict || verdict.status === "pending") return <span className="text-yellow-400">verifying…</span>;
  if (verdict.status === "not_sampled") return <span>not sampled (paid after 10 min)</span>;
  if (verdict.status === "done") {
    const text = verdict.passed ? `✓ verified · ${provider} paid` : "✗ failed · refunded, provider slashed";
    const color = verdict.passed ? "text-green-400" : "text-red-400";
    return verdict.tx_hash ? (
      <a href={explorerTx(verdict.tx_hash)} target="_blank" rel="noreferrer" className={`underline ${color}`}>
        {text}
      </a>
    ) : (
      <span className={color}>{text}</span>
    );
  }
  return <span className="text-gray-500" title={verdict.reason}>verification {verdict.status}</span>;
}
