import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, Text } from "@mantine/core";
import type { TrendPoint } from "../api/types";
import { formatCompactMoney, formatMoney } from "../lib/money";

interface Props {
  points: TrendPoint[];
  currency: string;
}

/** "2026-03" -> "Mar 26" */
function monthLabel(month: string): string {
  const [year, m] = month.split("-");
  const name = new Date(Number(year), Number(m) - 1, 1).toLocaleDateString("en-GB", {
    month: "short",
  });

  return `${name} ${year.slice(2)}`;
}

/**
 * Total payroll at each month end.
 *
 * One line, so no legend: the title names the series, and a legend box for
 * a single series is furniture. Every month converts at the same fixed
 * exchange rate, so the movement here is compensation decisions rather
 * than currency drift — which is the only reason the line is worth reading.
 */
export function PayrollTrendChart({ points, currency }: Props) {
  const data = points.map((point) => ({
    ...point,
    label: monthLabel(point.month),
  }));

  if (data.length === 0) {
    return (
      <Text c="dimmed" size="sm" py="xl" ta="center">
        No payroll history for this selection.
      </Text>
    );
  }

  return (
    <div className="viz-root">
      <ResponsiveContainer width="100%" height={280}>
        <LineChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 8 }}>
          <CartesianGrid vertical={false} stroke="var(--viz-grid)" strokeDasharray="2 4" />

          <XAxis
            dataKey="label"
            stroke="var(--viz-axis)"
            tick={{ fill: "var(--viz-text-muted)", fontSize: 11 }}
            tickLine={false}
            // 24 labels do not fit; showing every third keeps them readable.
            interval={Math.max(0, Math.floor(data.length / 8) - 1)}
          />

          <YAxis
            stroke="var(--viz-axis)"
            tick={{ fill: "var(--viz-text-muted)", fontSize: 12 }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(value: number) => formatCompactMoney(value, currency)}
            // Payroll never approaches zero, so a zero-based axis would
            // compress every real movement into a flat line. The axis is
            // labelled, and this is a trend rather than a magnitude
            // comparison, so a non-zero baseline is honest here.
            domain={["dataMin - dataMin * 0.05", "dataMax + dataMax * 0.02"]}
          />

          <Tooltip
            cursor={{ stroke: "var(--viz-axis)", strokeWidth: 1 }}
            content={({ active, payload }) => {
              if (!active || !payload?.length) return null;
              const row = payload[0].payload as (typeof data)[number];

              return (
                <Card withBorder shadow="sm" padding="xs" radius="sm">
                  <Text fw={600} size="sm">
                    {row.label}
                  </Text>
                  <Text size="sm">{formatMoney(row.total_cents, currency)}</Text>
                  <Text size="xs" c="dimmed">
                    {row.headcount.toLocaleString()} employees
                  </Text>
                </Card>
              );
            }}
          />

          <Line
            type="monotone"
            dataKey="total_cents"
            stroke="var(--viz-series-1)"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 5, strokeWidth: 2, stroke: "var(--viz-surface)" }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
