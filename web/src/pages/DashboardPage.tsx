import { useState } from "react";
import { Link } from "react-router-dom";
import {
  Alert,
  Anchor,
  Card,
  Grid,
  Group,
  SegmentedControl,
  Skeleton,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import type { GroupBy } from "../api/types";
import { useDistribution, useOutliers, useOverview, usePayrollTrend } from "../hooks/useApi";
import { StatCard } from "../components/StatCard";
import { DistributionChart } from "../components/DistributionChart";
import { PayrollTrendChart } from "../components/PayrollTrendChart";
import { formatCompactMoney, formatMoney } from "../lib/money";

const GROUP_OPTIONS: { value: GroupBy; label: string }[] = [
  { value: "department", label: "Department" },
  { value: "country", label: "Country" },
  { value: "job_level", label: "Level" },
];

export function DashboardPage() {
  const [groupBy, setGroupBy] = useState<GroupBy>("job_level");

  const overview = useOverview();
  const distribution = useDistribution(groupBy);
  const trend = usePayrollTrend(24);
  const outliers = useOutliers();

  const currency = overview.data?.currency ?? "USD";
  const salary = overview.data?.salary;

  // Payroll movement over the window, which is the number someone actually
  // wants from a 24-month trend.
  const points = trend.data?.points ?? [];
  const growth =
    points.length > 1 && points[0].total_cents > 0
      ? ((points[points.length - 1].total_cents - points[0].total_cents) /
          points[0].total_cents) *
        100
      : null;

  const outOfBand =
    (outliers.data?.counts.below_band ?? 0) + (outliers.data?.counts.above_band ?? 0);

  return (
    <Stack gap="lg">
      <div>
        <Title order={2}>Compensation overview</Title>
        <Text size="sm" c="dimmed">
          All figures converted to {currency} at a fixed reference rate, so movement
          reflects pay decisions rather than currency markets.
        </Text>
      </div>

      {overview.isError && (
        <Alert color="red" role="alert">
          {(overview.error as Error).message}
        </Alert>
      )}

      <Grid>
        <Grid.Col span={{ base: 12, sm: 6, lg: 3 }}>
          <StatCard
            label="Active headcount"
            value={overview.data?.headcount.toLocaleString() ?? "—"}
            isLoading={overview.isLoading}
          />
        </Grid.Col>

        <Grid.Col span={{ base: 12, sm: 6, lg: 3 }}>
          <StatCard
            label="Annual payroll"
            value={formatCompactMoney(overview.data?.total_annual_cents, currency)}
            detail={formatMoney(overview.data?.total_annual_cents, currency)}
            hint={growth !== null ? `${growth >= 0 ? "+" : ""}${growth.toFixed(1)}% over 24 months` : undefined}
            isLoading={overview.isLoading}
          />
        </Grid.Col>

        <Grid.Col span={{ base: 12, sm: 6, lg: 3 }}>
          <StatCard
            label="Median salary"
            value={formatCompactMoney(salary?.p50, currency)}
            detail={formatMoney(salary?.p50, currency)}
            hint={
              salary?.p25 && salary?.p75
                ? `p25–p75 ${formatCompactMoney(salary.p25, currency)}–${formatCompactMoney(salary.p75, currency)}`
                : undefined
            }
            isLoading={overview.isLoading}
          />
        </Grid.Col>

        <Grid.Col span={{ base: 12, sm: 6, lg: 3 }}>
          <StatCard
            label="Outside pay band"
            value={outliers.isLoading ? "—" : outOfBand.toLocaleString()}
            color={outOfBand > 0 ? "var(--viz-critical)" : undefined}
            hint={
              outliers.data
                ? `${outliers.data.counts.below_band} below · ${outliers.data.counts.above_band} above`
                : undefined
            }
            isLoading={outliers.isLoading}
          />
        </Grid.Col>
      </Grid>

      <Card withBorder padding="lg">
        <Group justify="space-between" align="center" mb="md">
          <div>
            <Title order={4}>Pay distribution</Title>
            <Text size="sm" c="dimmed">
              Median and the middle 50% of earners in each group.
            </Text>
          </div>
          {/* Filters sit in one row above the chart they control. */}
          <SegmentedControl
            value={groupBy}
            onChange={(next) => setGroupBy(next as GroupBy)}
            data={GROUP_OPTIONS}
            aria-label="Group distribution by"
          />
        </Group>

        {distribution.isLoading ? (
          <Skeleton height={280} />
        ) : (
          <DistributionChart groups={distribution.data?.groups ?? []} currency={currency} />
        )}
      </Card>

      <Grid>
        <Grid.Col span={{ base: 12, lg: 7 }}>
          <Card withBorder padding="lg" h="100%">
            <Title order={4}>Payroll over 24 months</Title>
            <Text size="sm" c="dimmed" mb="md">
              Total committed salary at each month end.
            </Text>

            {trend.isLoading ? (
              <Skeleton height={280} />
            ) : (
              <PayrollTrendChart points={points} currency={currency} />
            )}
          </Card>
        </Grid.Col>

        <Grid.Col span={{ base: 12, lg: 5 }}>
          <Card withBorder padding="lg" h="100%">
            <Title order={4}>Where the money goes</Title>
            <Text size="sm" c="dimmed" mb="md">
              Annual payroll by country.
            </Text>

            {overview.isLoading ? (
              <Skeleton height={240} />
            ) : (
              <Stack gap="xs">
                {(overview.data?.splits.country ?? [])
                  .slice()
                  .sort((a, b) => b.total_annual_cents - a.total_annual_cents)
                  .map((split) => {
                    const total = overview.data?.total_annual_cents ?? 1;
                    const share = (split.total_annual_cents / total) * 100;

                    return (
                      <div key={split.group}>
                        <Group justify="space-between" gap="xs">
                          <Text size="sm" fw={500}>
                            {split.group}
                          </Text>
                          <Text size="sm" className="numeric">
                            {formatCompactMoney(split.total_annual_cents, currency)}
                          </Text>
                        </Group>
                        {/* A proportion against a whole, so a bar rather
                            than another chart type. */}
                        <div
                          style={{
                            height: 6,
                            borderRadius: 3,
                            background: "var(--mantine-color-gray-2)",
                            overflow: "hidden",
                          }}
                        >
                          <div
                            style={{
                              width: `${share}%`,
                              height: "100%",
                              background: "var(--viz-series-1, #2a78d6)",
                            }}
                          />
                        </div>
                        <Text size="xs" c="dimmed">
                          {split.headcount.toLocaleString()} employees · {share.toFixed(1)}%
                        </Text>
                      </div>
                    );
                  })}
              </Stack>
            )}
          </Card>
        </Grid.Col>
      </Grid>

      <Text size="sm">
        <Anchor component={Link} to="/outliers">
          Review pay outliers and stale salaries →
        </Anchor>
      </Text>
    </Stack>
  );
}
