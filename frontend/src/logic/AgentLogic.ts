import { 
  createWalletClient, 
  createPublicClient, 
  http, 
  type Address, 
  type Hex, 
  encodeAbiParameters, 
  keccak256 
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { unichainSepolia } from "../config/chain";
import { CONTRACTS, ABIS } from "../config/contracts";
// Importarías la lógica de gateways de ENS
// import { getStorageProof } from "@ensdomains/unruggable-gateways"; 

const AGENT_PK = process.env.NEXT_PUBLIC_AGENT_PRIVATE_KEY as Hex;
const agentAccount = privateKeyToAccount(AGENT_PK);

const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL),
});

const agentClient = createWalletClient({
  account: agentAccount,
  chain: unichainSepolia,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL),
});

/**
 * LÓGICA DE TICKS: Alineada con el TickSpacing 60 del Hook
 */
const getTicks = (price: number, deviationPct: number) => {
  const tickSpacing = 60;
  const currentTick = Math.floor(Math.log(price) / Math.log(1.0001));
  
  // Calculamos el rango basado en la desviación (ej. 2% = 0.02)
  const tickDelta = Math.floor(Math.log(1 + deviationPct) / Math.log(1.0001));
  
  return {
    lower: Math.floor((currentTick - tickDelta) / tickSpacing) * tickSpacing,
    upper: Math.floor((currentTick + tickDelta) / tickSpacing) * tickSpacing
  };
};

export const startAgentMonitoring = (
  userAddress: Address,
  ensNode: Hex, // El nodehash real del ENS del usuario
  onLog: (m: string) => void,
  riskLevel: number 
) => {
  let isRunning = true;
  let lastPrice = 0;

  const runLoop = async () => {
    if (!isRunning) return;

    try {
      // 1. MONITOR DE PRECIO (Binance o Unichain Pool directamente)
      const res = await fetch("https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDC");
      const { price: priceStr } = await res.json();
      const currentPrice = parseFloat(priceStr);

      // 2. REGLA DE ACTIVACIÓN: Desviación > 2%
      const deviation = lastPrice === 0 ? 1 : Math.abs((currentPrice - lastPrice) / lastPrice);
      
      if (deviation > 0.02) {
        onLog(`[Agent]: 📉 Desviación del ${(deviation * 100).toFixed(2)}% detectada.`);

        // 3. GENERACIÓN DE STORAGE PROOF (ENSv2)
        // Aquí es donde usarías @ensdomains/unruggable-gateways
        // Simulamos el objeto de prueba que pide el gateway
        const storageProof = "0x..." as Hex; 

        // 4. PREPARACIÓN DE STRUCTS
        const { lower, upper } = getTicks(currentPrice, riskLevel === 3 ? 0.005 : 0.02);

        const signal = {
          currentPrice: BigInt(Math.floor(currentPrice * 1e18)),
          volatility: BigInt(riskLevel * 25), // Mock de volatilidad
          recommendedLower: lower,
          recommendedUpper: upper,
          riskLevel: BigInt(riskLevel),
          ensNode: ensNode,
          timestamp: BigInt(Math.floor(Date.now() / 1000)),
        };

        // IMPORTANTE: Ordenar currencies para el PoolKey
        const [c0, c1] = [CONTRACTS.EETH, CONTRACTS.EUSD].sort();

        const poolKey = {
          currency0: c0 as Address,
          currency1: c1 as Address,
          fee: 3000,
          tickSpacing: 60,
          hooks: CONTRACTS.HOOK
        };

        // 5. EJECUCIÓN CON LLAVE DEL AGENTE
        onLog(`[Agent]: 🚀 Inyectando Rebalanceo...`);
        
        const { request } = await publicClient.simulateContract({
          address: CONTRACTS.HOOK,
          abi: ABIS.HOOK,
          functionName: "processAgentSignal",
          args: [poolKey, userAddress, signal],
          account: agentAccount,
        });

        const hash = await agentClient.writeContract(request);
        onLog(`[Agent]: ✅ Transacción enviada: ${hash.slice(0, 10)}`);
        
        lastPrice = currentPrice;
      }
    } catch (err: any) {
      onLog(`[Agent Error]: ${err.message || "Falla en el loop"}`);
    }

    if (isRunning) setTimeout(runLoop, 30000); // Loop de 30 segundos
  };

  runLoop();
  return () => { isRunning = false; };
};