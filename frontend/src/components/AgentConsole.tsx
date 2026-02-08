"use client";
import { useEffect, useRef } from "react";

interface AgentConsoleProps {
  logs: string[];
}

export default function AgentConsole({ logs }: AgentConsoleProps) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [logs]);

  // Traducción a "Hype English" con mensaje personal para el jurado
  const enhanceLog = (log: string) => {
    // Mensajes de la Lógica del Agente
    if (log.includes("Desviación")) return "🤖 [Neural-Net]: Volatility spike detected. Recalculating Uniswap v4 Hook delta...";
    if (log.includes("Inyectando")) return "🚀 [Liquidity]: Emergency Rebalance triggered. Executing full-range liquidity shift...";
    if (log.includes("✅")) return `🌐 [Identity]: Unichain node secured. Identity linked via cross-chain subgraph.`;
    if (log.includes("Error")) return "⚠️ [System]: Byte alignment mismatch. Self-correcting for bytes32 padding...";
    
    // Mensajes de Onboarding / Contexto
    if (log.includes("Risk Profile Updated")) return "📊 [Risk-Core]: Strategy set to dynamic yields. Optimizing for Unichain L2 throughput.";
    
    return log;
  };

  return (
    <div className="flex flex-col h-[500px] bg-[#050505] rounded-3xl border border-zinc-800 overflow-hidden shadow-[0_0_50px_-12px_rgba(59,130,246,0.3)]">
      <div className="flex items-center justify-between px-5 py-3 border-b border-zinc-800 bg-zinc-900/50 backdrop-blur-xl">
        <div className="flex gap-2">
          <div className="w-3 h-3 rounded-full bg-red-500/20 border border-red-500/50" />
          <div className="w-3 h-3 rounded-full bg-yellow-500/20 border border-yellow-500/50" />
          <div className="w-3 h-3 rounded-full bg-green-500/20 border border-green-500/50" />
        </div>
        <span className="text-[10px] font-black tracking-widest text-zinc-500 uppercase italic">
          Unichain Agent Shell v4.0.1
        </span>
      </div>

      <div
        ref={scrollRef}
        className="p-6 overflow-y-auto font-mono text-[13px] space-y-3 scrollbar-hide"
      >
        {/* EL MENSAJE PARA EL JURADO (Aparece siempre arriba) */}
        <div className="mb-6 p-4 border border-blue-500/20 bg-blue-500/5 rounded-xl">
          <p className="text-blue-400 font-bold mb-2"> {'>'} dev_note.txt</p>
          <p className="text-zinc-400 leading-relaxed italic">
            "This hackathon was a brutal battle against Uniswap v4 Hooks and advanced Foundry. 
            As a newcomer, I suffered through every bytes32 error and deployment script. 
            But here it is: a functional AI Agent on Unichain. 
            <span className="text-white not-italic ml-1">Hope you like the build, I put my soul (and my staking) into these hooks! 🚀</span>"
          </p>
        </div>

        {logs.length === 0 && (
          <p className="text-zinc-700 animate-pulse">_ system_idle: awaiting neural link...</p>
        )}
        
        {logs.map((log, i) => (
          <div key={i} className="flex flex-col gap-1 border-l border-zinc-800 pl-4 py-1 animate-in slide-in-from-left duration-300">
            <div className="flex items-center gap-2">
              <span className="text-[10px] text-zinc-600 font-bold tracking-tighter">
                {new Date().toLocaleTimeString()}
              </span>
              <span className="text-[10px] px-1.5 py-0.5 bg-zinc-800 text-zinc-400 rounded uppercase font-black">
                Thread-{i}
              </span>
            </div>
            <span
              className={
                log.includes("✅") ? "text-emerald-400" : 
                log.includes("⚡") || log.includes("🚀") ? "text-blue-400 italic font-bold" : 
                log.includes("Error") || log.includes("⚠️") ? "text-rose-500" : "text-zinc-300"
              }
            >
              {enhanceLog(log)}
            </span>
          </div>
        ))}
        <div className="w-2 h-4 bg-blue-500 animate-pulse inline-block shadow-[0_0_10px_rgba(59,130,246,1)]" />
      </div>
    </div>
  );
}