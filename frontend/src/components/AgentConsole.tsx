"use client";
import { useEffect, useRef } from "react";

interface AgentConsoleProps {
  logs: string[];
}

export default function AgentConsole({ logs }: AgentConsoleProps) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) {
      // Usamos el método de acceso seguro para evitar errores de compilación
      el.scrollTop = el.scrollHeight;
    }
  }, [logs]);

  return (
    <div className="flex flex-col h-[500px] bg-black rounded-3xl border border-gray-800 overflow-hidden shadow-2xl">
      <div className="flex items-center justify-between px-5 py-3 border-b border-gray-800 bg-zinc-900">
        <div className="flex gap-2">
          <div className="w-3 h-3 rounded-full bg-red-500" />
          <div className="w-3 h-3 rounded-full bg-yellow-500" />
          <div className="w-3 h-3 rounded-full bg-green-500" />
        </div>
        <span className="text-xs font-mono text-gray-400">agent-core-v1.0.sh</span>
      </div>

      <div
        ref={scrollRef}
        className="p-4 overflow-y-auto font-mono text-sm space-y-2 scrollbar-hide"
      >
        {logs.length === 0 && (
          <p className="text-gray-600 animate-pulse">_ Waiting for wallet connection...</p>
        )}
        {logs.map((log, i) => (
          <div key={i} className="flex gap-2">
            <span className="text-zinc-500 shrink-0">[{i}]</span>
            <span
              className={
                log.includes("✅") ? "text-green-400" : 
                log.includes("🚨") ? "text-yellow-400" : 
                log.includes("Error") ? "text-red-400" : "text-primary"
              }
            >
              {log}
            </span>
          </div>
        ))}
        <div className="w-2 h-5 bg-primary animate-pulse inline-block ml-1" />
      </div>
    </div>
  );
}