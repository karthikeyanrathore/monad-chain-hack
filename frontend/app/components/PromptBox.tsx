"use client";

import { useState } from "react";
import type { Model } from "@/lib/models";
import { MODELS } from "@/lib/models";

interface PromptBoxProps {
  input: string;
  setInput: (value: string) => void;
  onSend: () => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  model: Model;
  setModel: (m: Model) => void;
  centered?: boolean;
}

export default function PromptBox({
  input,
  setInput,
  onSend,
  onKeyDown,
  model,
  setModel,
  centered,
}: PromptBoxProps) {
  const [showModelMenu, setShowModelMenu] = useState(false);

  return (
    <div className={`w-full ${centered ? "max-w-2xl" : "max-w-3xl mx-auto"}`}>
      {/* Input box — sirf textarea + send button, ismein model selector nahi */}
      <div className="flex items-end gap-2 rounded-2xl bg-[#2a2a2a] border border-white/10 px-3 py-2 focus-within:border-orange-500/50 transition">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          rows={1}
          placeholder="Ask anything…"
          className="flex-1 bg-transparent resize-none outline-none text-[15px] text-gray-100 placeholder-gray-500 py-1.5 max-h-40"
        />
        <button
          onClick={onSend}
          disabled={!input.trim()}
          className="shrink-0 rounded-full bg-orange-600 hover:bg-orange-500 disabled:bg-white/10 disabled:cursor-not-allowed w-8 h-8 flex items-center justify-center transition"
        >
          <svg width="16" height="16" viewBox="0 0 20 20" fill="white">
            <path d="M10 3l6 6h-4v8H8V9H4l6-6z" />
          </svg>
        </button>
      </div>

      {/* Model selector — box ke BAHAR, right side pe */}
      <div className="flex justify-end mt-2">
        <div className="relative">
          <button
            onClick={() => setShowModelMenu((v) => !v)}
            className="flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-sm font-medium text-gray-400 hover:bg-white/5 transition"
          >
            {model.name}
            <svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor" className="text-gray-500">
              <path d="M5.5 7.5L10 12l4.5-4.5H5.5z" />
            </svg>
          </button>
          {showModelMenu && (
            <div className="absolute top-full mt-1 right-0 w-56 rounded-xl bg-[#2a2a2a] border border-white/10 shadow-xl overflow-hidden z-10">
              {MODELS.map((m) => (
                <button
                  key={m.id}
                  onClick={() => {
                    setModel(m);
                    setShowModelMenu(false);
                  }}
                  className={`w-full text-left px-4 py-2.5 text-sm hover:bg-white/5 transition ${
                    m.id === model.id ? "text-orange-400" : "text-gray-200"
                  }`}
                >
                  {m.name}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}