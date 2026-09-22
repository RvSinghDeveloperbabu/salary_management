import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ErrorBar,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, Group, Table, Text } from "@mantine/core";
import type { DistributionGroup } from "../api/types";
import { formatCompactMoney, formatMoney } from "../lib/money";

interface Props {
  groups: DistributionGroup[];
  currency: string;
}

/**
 * Median pay per group, with the p25–p75 range drawn as a whisker.
 *
 * The range is the point. A median alone says "L4s earn 120k"; the spread
 * says whether that is a consistent band or an average of people paid very
 * differently for the same work, which is the thing an HR manager can act
 * on.
 *
 * One hue rather than a colour per group: every bar is the same measure, so
 * a categorical palette would falsely imply they are different kinds of
 * thing. Identity is carried by the axis label, not by colour.
 */
export function DistributionChart({ groups, currency }: Props) {
  const data = groups
    .filter((group) => group.p50 !== null)
    .map((group) => ({
      group: group.group,
      median: group.p50 as number,
      count: group.count,
      p25: group.p25 as number,
      p75: group.p75 as number,
      // Recharts draws an ErrorBar as [distance below, distance above],
      // not as absolute bounds.
      range: [
        (group.p50 as number) - (group.p25 as number),
        (group.p75 as number) - (group.p50 as number),
      ] as [number, number],
    }));

  if (data.length === 0) {
    return (
      <Text c="dimmed" size="sm" py="xl" ta="center">
        No salary data for this selection.
      </Text>
    );
  }

  // Horizontal bars: department and country names are long, and rotated
  // axis labels are harder to read than a taller chart.
  const height = Math.max(240, data.length * 44);

  return (
    <div className="viz-root">
      <ResponsiveContainer width="100%" height={height}>
        <BarChart data={data} layout="vertical" margin={{ top: 8, right: 72, bottom: 8, left: 8 }}>
          <CartesianGrid
            horizontal={false}
            stroke="var(--viz-grid)"
            strokeDasharray="2 4"
          />
          <XAxis
            type="number"
            tickFormatter={(value: number) => formatCompactMoney(value, currency)}
            stroke="var(--viz-axis)"
            tick={{ fill: "var(--viz-text-muted)", fontSize: 12 }}
            tickLine={false}
          />
          <YAxis
            type="category"
            dataKey="group"
            width={130}
            stroke="var(--viz-axis)"
            tick={{ fill: "var(--viz-text-primary)", fontSize: 12 }}
            tickLine={false}
            axisLine={false}
          />

          <Tooltip
            cursor={{ fill: "var(--viz-grid)", fillOpacity: 0.3 }}
            content={({ active, payload }) => {
              if (!active || !payload?.length) return null;
              const row = payload[0].payload as (typeof data)[number];

              return (
                <Card withBorder shadow="sm" padding="xs" radius="sm">
                  <Text fw={600} size="sm">
                    {row.group}
                  </Text>
                  <Text size="xs" c="dimmed">
                    {row.count.toLocaleString()} employees
                  </Text>
                  <Table withRowBorders={false} verticalSpacing={2} fz="xs" mt={4}>
                    <Table.Tbody>
                      <Table.Tr>
                        <Table.Td pr="sm">Median</Table.Td>
                        <Table.Td className="numeric">
                          {formatMoney(row.median, currency)}
                        </Table.Td>
                      </Table.Tr>
                      <Table.Tr>
                        <Table.Td pr="sm">p25–p75</Table.Td>
                        <Table.Td className="numeric">
                          {formatMoney(row.p25, currency)} – {formatMoney(row.p75, currency)}
                        </Table.Td>
                      </Table.Tr>
                    </Table.Tbody>
                  </Table>
                </Card>
              );
            }}
          />

          <Bar dataKey="median" radius={[0, 4, 4, 0]} barSize={18} isAnimationActive={false}>
            {data.map((row) => (
              <Cell key={row.group} fill="var(--viz-series-1)" />
            ))}
            {/* The whisker: p25 to p75 around the median. */}
            <ErrorBar
              dataKey="range"
              width={6}
              strokeWidth={2}
              stroke="var(--viz-text-muted)"
              direction="x"
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>

      <Group justify="flex-end" gap="lg" mt={4} pr="md">
        <Group gap={6}>
          <div
            style={{
              width: 12,
              height: 10,
              borderRadius: 2,
              background: "var(--viz-series-1)",
            }}
          />
          <Text size="xs" c="dimmed">
            Median
          </Text>
        </Group>
        <Group gap={6}>
          <div style={{ width: 12, height: 2, background: "var(--viz-text-muted)" }} />
          <Text size="xs" c="dimmed">
            p25–p75 range
          </Text>
        </Group>
      </Group>
    </div>
  );
}
