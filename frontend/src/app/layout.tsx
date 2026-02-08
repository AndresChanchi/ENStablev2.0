"use client";

import { WagmiProvider, createConfig, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { unichainSepolia } from "../config/chain";
import { injected } from 'wagmi/connectors';

// Configuración de Wagmi
const config = createConfig({
  chains: [unichainSepolia],
  connectors: [injected()],
  transports: {
    [unichainSepolia.id]: http(),
  },
});

const queryClient = new QueryClient();

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <head>
        {/* Usando el archivo compilado de Tailwind v4 */}
        <link rel="stylesheet" href="./output.css" />
        <link rel="icon" href="./favicon.ico" />
      </head>
      <body>
        <WagmiProvider config={config}>
          <QueryClientProvider client={queryClient}>
            {children}
          </QueryClientProvider>
        </WagmiProvider>
      </body>
    </html>
  );
}