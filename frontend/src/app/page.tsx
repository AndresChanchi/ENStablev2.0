"use client";

import { useState, useEffect } from "react";
import { useAccount, useConnect, useDisconnect, useEnsName } from "wagmi";
import { startAgentMonitoring } from "../logic/AgentLogic";
import AgentConsole from "../components/AgentConsole";
import LiquidityCard from "../components/LiquidityCard";
import PriceChart from "../components/PriceChart";

export default function App() {
  const { address, isConnected } = useAccount();
  // FIX: En Wagmi v2 es 'isPending', no 'isLoading'
  const { connect, connectors, isPending: isConnecting } = useConnect(); 
  const { disconnect } = useDisconnect();
  
  // OBTENER ENS REAL (Si existe en Mainnet/Sepolia)
  const { data: ensName } = useEnsName({ address });

  // ESTADOS
  const [logs, setLogs] = useState<string[]>([]);
  const [price, setPrice] = useState<number>(0);
  
  // ESTADOS IDENTITY/RISK
  const [riskLevel, setRiskLevel] = useState<number | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const addLog = (message: string) => {
    setLogs((prev) => [...prev, message]);
  };

  // Check inicial de Identidad
  useEffect(() => {
    if (isConnected && !riskLevel) {
      const timer = setTimeout(() => {
        setShowOnboarding(true);
        addLog("⚠️ Identity check: Risk Profile required for ENS Node linkage.");
      }, 500);
      return () => clearTimeout(timer);
    }
  }, [isConnected, riskLevel]);

  const handleSelectRisk = (level: number) => {
    setRiskLevel(level);
    setShowOnboarding(false);
    
    const riskName = level === 1 ? 'Conservative' : level === 2 ? 'Balanced' : 'Aggressive';
    addLog(`✅ Risk Profile Updated: ${riskName} (Level ${level})`);
    addLog(`🔗 Linked to Identity: ${ensName || address?.slice(0, 8) + "..."}`);
  };

  // Ticker (Binance)
  useEffect(() => {
    const updateVisualPrice = async () => {
      try {
        const res = await fetch("https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDC");
        const data = (await res.json()) as { price: string };
        setPrice(parseFloat(data.price));
      } catch (e) {
        console.error("Ticker error");
      }
    };
    updateVisualPrice();
    const interval = setInterval(updateVisualPrice, 5000);
    return () => clearInterval(interval);
  }, []);

  // Agente
  useEffect(() => {
    if (isConnected && address && riskLevel) {
      // Pasamos el ensName real o simulado al agente
      const stopAgent = startAgentMonitoring(address, ensName, addLog, riskLevel); 
      return () => stopAgent();
    }
  }, [isConnected, address, riskLevel, ensName]);

  const handleConnect = () => {
    if (connectors.length > 0) {
      connect({ connector: connectors[0] });
    }
  };

  if (!mounted) return null;

  return (
    <div className="container-responsive py-10 min-h-screen relative">
      <header className="flex justify-between items-center mb-10">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 bg-primary rounded-2xl shadow-lg shadow-primary/20 flex items-center justify-center text-white font-bold text-xl">
            E
          </div>
          <div>
            <h1 className="hero-title text-2xl leading-none">Enstable.ai</h1>
            <p className="text-[10px] text-zinc-400 font-bold tracking-[0.2em] uppercase mt-1">Unichain L2 Agent</p>
          </div>
        </div>

        {/* BOTÓN CONECTAR */}
        <button 
          onClick={isConnected ? () => disconnect() : handleConnect}
          disabled={isConnecting}
          className={`px-6 py-2.5 rounded-2xl border font-bold text-sm transition-all active:scale-95 flex items-center gap-2
            ${isConnected 
              ? 'bg-secondary/10 border-secondary/20 text-main hover:bg-red-50 hover:text-red-600 hover:border-red-100' 
              : 'bg-primary border-primary text-white shadow-lg shadow-primary/20 hover:brightness-110'}`}
        >
          {isConnecting ? (
            <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
          ) : isConnected ? (
            <>
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
              {/* Muestra el ENS si existe, si no recorta la address */}
              {ensName || `${address?.slice(0, 6)}...${address?.slice(-4)}`}
            </>
          ) : (
            "Connect Wallet"
          )}
        </button>
      </header>

      {/* MODAL ONBOARDING */}
      {showOnboarding && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-md z-50 flex items-center justify-center p-4 animate-in fade-in duration-300">
          <div className="bg-white rounded-[40px] p-8 max-w-md w-full shadow-2xl border border-primary/20 scale-100 animate-in zoom-in-95 duration-300">
            <div className="flex justify-center mb-4">
               <div className="w-16 h-16 bg-blue-50 rounded-full flex items-center justify-center text-3xl">🛡️</div>
            </div>
            <h3 className="text-2xl font-black text-center mb-2 text-zinc-800">Set Your Identity</h3>
            <p className="text-zinc-500 text-center mb-8 text-sm px-4">
              {ensName ? (
                <>Welcome back, <span className="font-bold text-primary">{ensName}</span>.</>
              ) : (
                "No ENS detected. Using temporary Identity."
              )}
              {" "}Select your risk profile to link with your node on Unichain.
            </p>
            
            <div className="grid gap-3">
              {[
                { id: 1, label: "Conservative", desc: "Low Volatility • Stable Yields", color: "bg-green-500", border: "hover:border-green-400" },
                { id: 2, label: "Balanced", desc: "Medium Risk • Optimized Growth", color: "bg-orange-400", border: "hover:border-orange-400" },
                { id: 3, label: "Aggressive", desc: "High Volatility • Max APY", color: "bg-red-500", border: "hover:border-red-500" }
              ].map((p) => (
                <button 
                  key={p.id}
                  onClick={() => handleSelectRisk(p.id)}
                  className={`flex items-center justify-between p-5 rounded-3xl border-2 border-zinc-100 transition-all group bg-zinc-50/50 hover:bg-white hover:shadow-lg hover:-translate-y-1 ${p.border}`}
                >
                  <div className="text-left">
                    <p className="font-black text-lg text-zinc-700 group-hover:text-black">{p.label}</p>
                    <p className="text-xs text-zinc-400 font-medium">{p.desc}</p>
                  </div>
                  <div className={`w-3 h-3 rounded-full ${p.color} ring-4 ring-white shadow-sm opacity-50 group-hover:opacity-100 scale-75 group-hover:scale-125 transition-all`} />
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 mt-4">
        <div className="lg:col-span-4 space-y-8">
          {/* Pasamos la función para reabrir el modal */}
          <LiquidityCard 
            currentPrice={price} 
            onChangeIdentity={() => setShowOnboarding(true)} 
            userEns={ensName}
          />
          <div className="h-[280px] bg-surface rounded-[32px] p-4 border border-secondary/10">
            <PriceChart currentPrice={price} />
          </div>
        </div>

        <div className="lg:col-span-8">
          <AgentConsole logs={logs} />
        </div>
      </div>
    </div>
  );
}