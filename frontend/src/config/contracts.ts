import EnstableHook from "./abis-json/EnstableHook.json";
import IdentityVault from "./abis-json/IdentityVault.json";
import MockEETH from "./abis-json/MockERC20EETH.json";
import MockEUSD from "./abis-json/MockERC20EUSD.json";

export const CONTRACTS = {
  HOOK: (process.env.NEXT_PUBLIC_HOOK_ADDRESS || "0x0") as `0x${string}`,
  VAULT: (process.env.NEXT_PUBLIC_VAULT_ADDRESS || "0x0") as `0x${string}`,
  EETH: (process.env.NEXT_PUBLIC_EETH_ADDRESS || "0x0") as `0x${string}`,
  EUSD: (process.env.NEXT_PUBLIC_EUSD_ADDRESS || "0x0") as `0x${string}`,
};

// Algunos compiladores exportan el ABI directo, otros dentro de una propiedad .abi
// Esta lógica detecta cuál es la correcta
const getAbi = (json: any) => {
  if (json.abi) return json.abi;
  if (Array.isArray(json)) return json;
  return json;
};

export const ABIS = {
  HOOK: getAbi(EnstableHook),
  VAULT: getAbi(IdentityVault),
  EETH: getAbi(MockEETH),
  EUSD: getAbi(MockEUSD),
};