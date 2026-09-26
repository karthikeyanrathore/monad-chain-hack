"use client";

import { useState, useRef, useEffect } from "react";
import PromptBox from "./PromptBox";
import { MODELS, type Model } from "@/lib/models";

interface Message {
  role: "user" | "assistant";
  text: string;
}

export default function ChatClient() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [model, setModel] = useState<Model>(MODELS[0]);
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  const handleSend = async () => {
    if (!input.trim()) return;
    const userMsg: Message = { role: "user", text: input };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setLoading(true);

    try {
      await new Promise((r) => setTimeout(r, 800));
      setMessages((prev) => [
        ...prev,
        { role: "assistant", text: `(${model.name} se reply yahan aayega)` },
      ]);
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
        <header className="flex items-center justify-end px-4 py-3 border-b border-white/10">
          <div className="w-8 h-8 rounded-full bg-gradient-to-br from-orange-400 to-orange-600" />
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
                    className={`max-w-[80%] rounded-2xl px-4 py-2.5 text-[15px] leading-relaxed ${
                      m.role === "user"
                        ? "bg-orange-600/90 text-white"
                        : "bg-[#2a2a2a] text-gray-100"
                    }`}
                  >
                    {m.text}
                  </div>
                </div>
              ))}
              {loading && (
                <div className="flex justify-start">
                  <div className="bg-[#2a2a2a] rounded-2xl px-4 py-2.5 text-gray-400 text-sm">
                    Thinking…
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
            />
          </div>
        )}
      </main>
    </div>
  );
}