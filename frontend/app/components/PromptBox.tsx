"use client";

import type { Model } from "@/lib/models";
import { MODELS } from "@/lib/models";
import { formatMon } from "@/lib/api";

interface PromptBoxProps {
  input: string;
  setInput: (value: string) => void;
  onSend: () => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  model: Model;
  setModel: (m: Model) => void;
  centered?: boolean;
  prices?: Record<string, string>;
  disabled?: boolean;
}

export default function PromptBox({
  input,
  setInput,
  onSend,
  onKeyDown,
  model,
  setModel,
  centered,
  prices = {},
  disabled,
}: PromptBoxProps) {
  return (
    <div className={`w-full ${centered ? "max-w-2xl" : "max-w-3xl mx-auto"}`}>
      <div className="rounded-2xl border border-line bg-panel/80 backdrop-blur shadow-[0_0_0_1px_rgba(131,110,249,0.05),0_20px_60px_-20px_rgba(131,110,249,0.35)] focus-within:border-violet/50 transition">
        <textarea
          id="prompt"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          rows={centered ? 3 : 1}
          placeholder="Ask anything. The answer gets verified on Monad."
          className="block w-full resize-none bg-transparent px-4 pt-4 pb-2 text-[15px] text-ink placeholder:text-muted outline-none max-h-48"
        />
        <div className="flex items-center justify-between gap-3 px-3 pb-3">
          {/* Model picker: price is what one prompt costs from your deposit */}
          <div role="radiogroup" aria-label="Model" className="flex rounded-xl bg-black/30 p-1 border border-line">
            {MODELS.map((m) => {
              const active = m.id === model.id;
              return (
                <button
                  key={m.id}
                  role="radio"
                  aria-checked={active}
                  onClick={() => setModel(m)}
                  className={`rounded-lg px-3 py-1.5 text-xs transition ${
                    active ? "bg-violet text-white shadow-[0_0_20px_-4px_rgba(131,110,249,0.8)]" : "text-muted hover:text-ink"
                  }`}
                >
                  <span className="font-medium">{m.name}</span>
                  {prices[m.id] && (
                    <span className={`ml-1.5 font-mono ${active ? "text-white/75" : "text-muted"}`}>{formatMon(prices[m.id])} MON</span>
                  )}
                </button>
              );
            })}
          </div>
          <button
            onClick={onSend}
            disabled={!input.trim() || disabled}
            aria-label="Send"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-violet to-[#5b45e0] text-white shadow-[0_8px_24px_-8px_rgba(131,110,249,0.9)] transition hover:brightness-110 disabled:from-white/10 disabled:to-white/10 disabled:shadow-none disabled:cursor-not-allowed"
          >
            <svg width="16" height="16" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10 3l6 6h-4v8H8V9H4l6-6z" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
