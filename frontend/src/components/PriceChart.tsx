"use client";

import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Filler,
  Legend,
  type ChartOptions,
} from "chart.js";
import { Line } from "react-chartjs-2";
import { useEffect, useState } from "react";

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Filler,
  Legend,
);

interface PriceChartProps {
  currentPrice: number;
}

export default function PriceChart({ currentPrice }: PriceChartProps) {
  const [chartData, setChartData] = useState<{ label: string; value: number }[]>([]);
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
    const fetchHistory = async () => {
      try {
        const res = await fetch(
          "https://api.binance.com/api/v3/klines?symbol=ETHUSDC&interval=1m&limit=30"
        );
        const data = await res.json();
        const history = data.map((d: any) => ({
          label: new Date(d[0]).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          value: parseFloat(d[4])
        }));
        setChartData(history);
      } catch (e) {
        console.error("Error loading history", e);
      }
    };
    fetchHistory();
  }, []);

  useEffect(() => {
    if (currentPrice === 0) return;

    setChartData((prev) => {
      const now = new Date().toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
      
      const lastEntry = prev.length > 0 ? prev[prev.length - 1] : null;
      
      // Si el último segundo es el mismo, solo actualizamos el precio
      if (lastEntry && lastEntry.label === now) {
        const updated = [...prev];
        updated[updated.length - 1] = { ...lastEntry, value: currentPrice };
        return updated;
      }

      // Si es un segundo nuevo, añadimos punto y borramos el más viejo (slice)
      const newData = [...prev, { label: now, value: currentPrice }];
      return newData.slice(-30); 
    });
  }, [currentPrice]);

  if (!isMounted) return <div className="h-full bg-surface animate-pulse rounded-[32px]" />;

  const data = {
    labels: chartData.map((d) => d.label),
    datasets: [
      {
        fill: true,
        label: "ETH/USDC",
        data: chartData.map((d) => d.value),
        borderColor: "#ff9689",
        backgroundColor: "rgba(255, 150, 137, 0.1)",
        tension: 0.4,
        pointRadius: 0,
        borderWidth: 2,
      },
    ],
  };

  const options: ChartOptions<"line"> = {
    responsive: true,
    maintainAspectRatio: false,
    animation: {
      duration: 800, 
      easing: 'linear'
    },
    plugins: { 
      legend: { display: false },
      tooltip: { enabled: true }
    },
    scales: {
      x: { display: false },
      y: {
        display: true,
        position: 'right',
        grid: { color: "rgba(0,0,0,0.02)" },
        ticks: {
          font: { size: 9 },
          callback: (value) => `$${Number(value).toLocaleString()}`
        },
        grace: '10%' 
      }
    }
  };

  return (
    <div className="bg-surface p-6 rounded-[32px] border border-secondary/20 shadow-sm h-full flex flex-col">
      <div className="flex justify-between items-center mb-4">
        <div>
          <h3 className="text-main font-bold">ETH / USDC</h3>
          <p className="text-xs text-zinc-400">Live Visual Feed</p>
        </div>
        <div className="text-right">
          <span className="text-primary font-bold text-xl">
            ${currentPrice > 0 ? currentPrice.toLocaleString("en-US", { minimumFractionDigits: 2 }) : "---"}
          </span>
        </div>
      </div>
      <div className="flex-grow min-h-[150px]">
        {chartData.length > 0 ? (
          <Line data={data} options={options} />
        ) : (
          <div className="h-full flex items-center justify-center text-zinc-300 text-sm">
            Syncing Market...
          </div>
        )}
      </div>
    </div>
  );
}