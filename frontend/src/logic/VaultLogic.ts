import { parseUnits } from "viem";

export const VaultLogic = {
  /**
   * Convierte el input de texto (ej: "0.1") a BigInt (ej: 100000000000000000n)
   */
  formatDeposit: (amount: string): bigint => {
    if (!amount || isNaN(parseFloat(amount))) return 0n;
    try {
      return parseUnits(amount, 18);
    } catch {
      return 0n;
    }
  },

  /**
   * Cálculo visual para mostrar equivalencia en dólares en el UI
   */
  calculateEstimation: (amount: string, price: number): string => {
    const numAmount = parseFloat(amount);
    if (!numAmount || !price) return "0.00";
    return (numAmount * price).toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  },

  /**
   * CRÍTICO: Calcula los Ticks para Uniswap v4.
   * Uniswap requiere que los ticks sean múltiplos del "TickSpacing" (60).
   * Si no son exactos, la transacción falla (Revert).
   */
  calculateTicks: (price: number, spread: number = 0.05) => { // Spread del 5% para asegurar rango
    const TICK_SPACING = 60;
    
    // 1. Calcular el Tick central basado en el precio: log_1.0001(price)
    // Nota: Asumimos que el token0 es ETH. Si el precio es 2500, el tick es ~78245
    const currentTick = Math.floor(Math.log(price) / Math.log(1.0001));
    
    // 2. Calcular la amplitud del rango
    const tickDelta = Math.floor(Math.log(1 + spread) / Math.log(1.0001));
    
    // 3. Definir rangos crudos
    let lowerRaw = currentTick - tickDelta;
    let upperRaw = currentTick + tickDelta;

    // 4. AJUSTE OBLIGATORIO: Redondear al múltiplo de 60 más cercano
    // Esto es lo que soluciona el error "Falta límite de gas"
    const lower = Math.floor(lowerRaw / TICK_SPACING) * TICK_SPACING;
    const upper = Math.floor(upperRaw / TICK_SPACING) * TICK_SPACING;

    // 5. Seguridad: Upper siempre debe ser mayor que Lower
    // Si están muy cerca, forzamos una separación de 120 ticks
    if (upper <= lower) {
        return { 
            lower: lower, 
            upper: lower + (TICK_SPACING * 2) 
        };
    }

    return { lower, upper };
  }
};