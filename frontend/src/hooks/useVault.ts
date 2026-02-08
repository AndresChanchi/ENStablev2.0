"use client";

import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { CONTRACTS, ABIS } from "../config/contracts";
import { VaultLogic } from "../logic/VaultLogic";
import { parseUnits, type Address } from "viem";
import { useState } from "react";

export function useVault() {
  const { address } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const [isApproving, setIsApproving] = useState(false);

  // --- LECTURAS ---
  const { data: balanceEETH, refetch: refetchEETH } = useReadContract({
    address: CONTRACTS.EETH,
    abi: ABIS.EETH,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  const { data: balanceEUSD, refetch: refetchEUSD } = useReadContract({
    address: CONTRACTS.EUSD,
    abi: ABIS.EUSD,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  const { data: allowanceEETH, refetch: refetchAllowEETH } = useReadContract({
    address: CONTRACTS.EETH,
    abi: ABIS.EETH,
    functionName: "allowance",
    args: address ? [address, CONTRACTS.VAULT] : undefined,
    query: { enabled: !!address }
  });

  const { data: allowanceEUSD, refetch: refetchAllowEUSD } = useReadContract({
    address: CONTRACTS.EUSD,
    abi: ABIS.EUSD,
    functionName: "allowance",
    args: address ? [address, CONTRACTS.VAULT] : undefined,
    query: { enabled: !!address }
  });

  const { data: position, refetch: refetchPosition } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: ABIS.VAULT,
    functionName: "getPosition",
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  const { data: ensNode } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: ABIS.VAULT,
    functionName: "userNodes", 
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  // --- ACCIONES ---

  // 1. FAUCET: Ahora te da 1 Millón de EUSD para que nunca falte
  const claimFaucet = async () => {
    if (!address) return;
    await writeContractAsync({
      address: CONTRACTS.EETH,
      abi: ABIS.EETH,
      functionName: "mint",
      args: [address, parseUnits("100", 18)],
    });
    return await writeContractAsync({
      address: CONTRACTS.EUSD,
      abi: ABIS.EUSD,
      functionName: "mint",
      args: [address, parseUnits("1000000", 18)], 
    });
  };

  // 2. PERMISOS: Ejecuta esto si el depósito falla
  const setupVaultPermissions = async () => {
    await writeContractAsync({
      address: CONTRACTS.VAULT,
      abi: ABIS.VAULT,
      functionName: "allowToken",
      args: [CONTRACTS.EETH],
    });
    return await writeContractAsync({
      address: CONTRACTS.VAULT,
      abi: ABIS.VAULT,
      functionName: "allowToken",
      args: [CONTRACTS.EUSD],
    });
  };

  // 3. APPROVE: Aprobación infinita
  const approve = async (tokenAddress: Address, abi: any) => {
    setIsApproving(true);
    try {
      return await writeContractAsync({
        address: tokenAddress,
        abi: abi,
        functionName: "approve",
        args: [CONTRACTS.VAULT, parseUnits("1000000000000", 18)],
      });
    } finally {
      setIsApproving(false);
    }
  };

  // 4. DEPOSIT: RANGOS FIJOS (Para evitar errores de precio/matemática)
  const deposit = async (amount: string) => {
    const bigAmount = parseUnits(amount, 18);
    
    // Forzamos orden de tokens
    const tokens = [CONTRACTS.EETH, CONTRACTS.EUSD].sort();
    
    const poolKey = {
      currency0: tokens[0] as Address,
      currency1: tokens[1] as Address,
      fee: 3000,
      tickSpacing: 60,
      hooks: CONTRACTS.HOOK
    };

    // Usamos Ticks manuales que cubren un rango gigante (Modo Emergencia)
    // Esto hace que la pool siempre acepte el depósito
    const lower = -887220; // Rango máximo inferior
    const upper = 887220;  // Rango máximo superior

    return await writeContractAsync({
      address: CONTRACTS.VAULT,
      abi: ABIS.VAULT,
      functionName: "deposit",
      args: [poolKey, bigAmount, lower, upper],
    });
  };

  const withdraw = async () => {
    const tokens = [CONTRACTS.EETH, CONTRACTS.EUSD].sort();
    const poolKey = {
      currency0: tokens[0],
      currency1: tokens[1],
      fee: 3000,
      tickSpacing: 60,
      hooks: CONTRACTS.HOOK
    };
    return await writeContractAsync({
      address: CONTRACTS.VAULT,
      abi: ABIS.VAULT,
      functionName: "withdraw",
      args: [poolKey, 0n], 
    });
  };

  return {
    balanceEETH: balanceEETH as bigint | undefined,
    balanceEUSD: balanceEUSD as bigint | undefined,
    allowanceEETH: allowanceEETH as bigint | undefined,
    allowanceEUSD: allowanceEUSD as bigint | undefined,
    stakedBalance: position ? (position as any).liquidity : 0n,
    hasIdentity: !!ensNode && ensNode !== "0x0000000000000000000000000000000000000000000000000000000000000000",
    isApproving,
    claimFaucet,
    setupVaultPermissions,
    approve,
    deposit,
    withdraw,
    refetchAll: () => {
      refetchEETH();
      refetchEUSD();
      refetchAllowEETH();
      refetchAllowEUSD();
      refetchPosition();
    }
  };
}