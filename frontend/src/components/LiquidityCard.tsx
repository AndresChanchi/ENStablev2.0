"use client";

import { useState, useMemo } from "react";
import { useVault } from "../hooks/useVault";
import { formatEther, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { ABIS, CONTRACTS } from "../config/contracts";

export default function LiquidityCard({ currentPrice = 0, userEns }: any) {
  const [amountETH, setAmountETH] = useState<string>("0.1");
  const [loading, setLoading] = useState(false);
  
  const { isConnected } = useAccount();
  const { 
    balanceEETH,
    balanceEUSD,
    allowanceEETH,
    allowanceEUSD,
    stakedBalance, 
    hasIdentity, 
    claimFaucet, 
    approve, 
    deposit, 
    withdraw, 
    setupVaultPermissions,
    refetchAll 
  } = useVault();

  // 1. Cálculos de UI Simplificados
  // Usamos una cantidad fija alta para el "Approve" de EUSD para evitar errores de cálculo
  const amountToApproveEUSD = useMemo(() => parseUnits("1000000", 18), []);
  
  const amountToDepositEETH = useMemo(() => {
    try { return parseUnits(amountETH || "0", 18); } catch { return 0n; }
  }, [amountETH]);

  // 2. Validaciones de estado
  // Verificamos si tienes al menos algo de tokens (el Faucet te da de sobra)
  const hasTokens = (balanceEETH && balanceEETH > 0n) && (balanceEUSD && balanceEUSD > 0n);

  // Verificamos permisos
  const needsApproveEETH = allowanceEETH !== undefined && allowanceEETH < amountToDepositEETH;
  // Si el allowance es menor a un monto razonable (ej. 10k EUSD), pedimos approve
  const needsApproveEUSD = allowanceEUSD !== undefined && allowanceEUSD < parseUnits("10000", 18);
  
  const hasInVault = stakedBalance && stakedBalance > 0n;

  const handleAction = async () => {
    if (!isConnected) return alert("Please connect your wallet first");
    setLoading(true);
    try {
      if (!hasTokens) {
        // Paso 1: Faucet
        await claimFaucet();
        alert("Tokens received! Please wait for balance update.");
      } else if (needsApproveEETH) {
        // Paso 2: Approve EETH
        await approve(CONTRACTS.EETH, ABIS.EETH);
      } else if (needsApproveEUSD) {
        // Paso 3: Approve EUSD
        await approve(CONTRACTS.EUSD, ABIS.EUSD);
      } else {
        // Paso 4: Deposit (Usando la función de emergencia con ticks fijos)
        await deposit(amountETH);
        alert("Deposit successful!");
      }
      
      // Refrescar datos después de cada acción exitosa
      setTimeout(() => refetchAll(), 2000);
    } catch (e: any) {
      console.error("Action failed:", e);
      // Extraemos el mensaje de error de viem si existe
      const msg = e.shortMessage || e.message || "Transaction failed";
      alert("Error: " + msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="bg-white w-full p-6 rounded-[32px] border border-zinc-200 shadow-xl text-zinc-900">
      <div className="flex flex-col gap-5">
        <div className="flex justify-between items-center">
          <div className="flex flex-col">
            <h2 className="font-black text-2xl tracking-tight leading-none">Vault Liquidity</h2>
            <span className="text-[10px] text-zinc-400 font-bold mt-1">UNISWAP V4 • FULL RANGE</span>
          </div>
          <div className={`px-3 py-1 rounded-full text-[10px] font-bold ${hasIdentity ? 'bg-green-100 text-green-600' : 'bg-red-100 text-red-600'}`}>
            {hasIdentity ? (userEns || "IDENTITY ACTIVE") : "NO IDENTITY"}
          </div>
        </div>

        {/* Muestra de Balances Reales */}
        <div className="grid grid-cols-2 gap-2 text-[10px] font-bold uppercase">
          <div className="bg-zinc-50 p-3 rounded-2xl border border-zinc-100">
            <div className="text-zinc-400 mb-1">Balance EETH</div>
            <div className="text-sm text-zinc-800">{balanceEETH ? Number(formatEther(balanceEETH)).toLocaleString() : "0.00"}</div>
          </div>
          <div className="bg-zinc-50 p-3 rounded-2xl border border-zinc-100">
            <div className="text-zinc-400 mb-1">Balance EUSD</div>
            <div className="text-sm text-zinc-800">{balanceEUSD ? Number(formatEther(balanceEUSD)).toLocaleString() : "0.00"}</div>
          </div>
        </div>

        {/* Input Principal */}
        <div className="bg-zinc-100 p-4 rounded-2xl border border-zinc-200">
          <label className="text-[10px] font-black text-zinc-400 uppercase">Amount to Stake</label>
          <div className="flex items-center gap-2 mt-1">
            <input
              type="number"
              value={amountETH}
              onChange={(e) => setAmountETH(e.target.value)}
              className="bg-transparent text-3xl font-bold w-full outline-none"
              placeholder="0.1"
            />
            <span className="font-black text-primary px-3 py-1 bg-white rounded-xl shadow-sm">EETH</span>
          </div>
        </div>

        {/* Botón de Acción Dinámico */}
        {!hasInVault ? (
          <button
            onClick={handleAction}
            disabled={loading}
            className="w-full py-4 bg-zinc-900 text-white rounded-2xl font-bold hover:bg-black transition-all disabled:opacity-50 shadow-lg active:scale-[0.98]"
          >
            {loading ? "Processing..." : 
             !hasTokens ? "1. Get Test Tokens" : 
             needsApproveEETH ? "2. Approve EETH" : 
             needsApproveEUSD ? "3. Approve EUSD" : 
             "4. Deposit to Vault"}
          </button>
        ) : (
          <div className="flex flex-col gap-2">
             <div className="text-center py-2 bg-green-50 text-green-600 text-[10px] font-bold rounded-lg border border-green-100">
              ✅ POSITION ACTIVE IN VAULT
            </div>
            <button
              onClick={async () => {
                setLoading(true);
                try { await withdraw(); refetchAll(); } catch(e) {} finally { setLoading(false); }
              }}
              className="w-full py-4 bg-red-500 text-white rounded-2xl font-bold hover:bg-red-600 transition-all shadow-md"
            >
              Withdraw Everything
            </button>
          </div>
        )}

        <hr className="border-zinc-100" />

        <button 
          onClick={async () => {
            setLoading(true);
            try { 
              await setupVaultPermissions(); 
              alert("Vault permissions initialized!");
            } catch(e) {} finally { setLoading(false); }
          }}
          className="text-[9px] text-zinc-300 hover:text-primary transition-colors uppercase font-bold text-center tracking-widest"
        >
          ⚙️ Emergency: Re-initialize Vault (allowToken)
        </button>
      </div>
    </div>
  );
}