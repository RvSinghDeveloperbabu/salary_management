import { useState } from "react";
import { Link } from "react-router-dom";
import {
  Alert,
  Anchor,
  Badge,
  Card,
  Center,
  Group,
  Loader,
  Stack,
  Table,
  Tabs,
  Text,
  Title,
} from "@mantine/core";
import type { OutlierFinding } from "../api/types";
import { useOutliers } from "../hooks/useApi";
import { formatDate, formatMoney, formatRatio } from "../lib/money";

type TabKey = "below" | "above" | "stale";

/**
 * The pay review screen: who is underpaid, who is overpaid, and who has
 * been forgotten.
 *
 * Amounts are shown in each employee's own currency, because a pay band is
 * defined in that currency. Converting to USD first would compare a Polish
 * salary to a Polish band through two conversions for no gain.
 */
export function OutliersPage() {
  const [tab, setTab] = useState<TabKey>("below");
  const { data, isLoading, isError, error } = useOutliers();

  if (isLoading) {
    return (
      <Center py="xl">
        <Loader />
      </Center>
    );
  }

  if (isError || !data) {
    return (
      <Alert color="red" role="alert">
        {(error as Error)?.message ?? "Could not load the pay review."}
      </Alert>
    );
  }

  const tabs: { key: TabKey; label: string; findings: OutlierFinding[]; colour: string }[] = [
    { key: "below", label: "Below band", findings: data.below_band, colour: "red" },
    { key: "above", label: "Above band", findings: data.above_band, colour: "orange" },
    { key: "stale", label: `No change in ${data.stale_after_months}+ months`, findings: data.stale, colour: "gray" },
  ];

  const active = tabs.find((t) => t.key === tab)!;

  return (
    <Stack>
      <div>
        <Title order={2}>Pay review</Title>
        <Text size="sm" c="dimmed">
          {data.currency_note}
        </Text>
      </div>

      <Tabs value={tab} onChange={(next) => setTab((next as TabKey) ?? "below")}>
        <Tabs.List>
          {tabs.map((item) => (
            <Tabs.Tab
              key={item.key}
              value={item.key}
              rightSection={
                // Not `circle`: a circular badge clips at three digits, and
                // the stale count runs into the thousands — it rendered as
                // "1.." for 1,734.
                <Badge size="sm" variant="light" color={item.colour}>
                  {item.findings.length.toLocaleString()}
                </Badge>
              }
            >
              {item.label}
            </Tabs.Tab>
          ))}
        </Tabs.List>
      </Tabs>

      <Card withBorder padding={0}>
        {active.findings.length === 0 ? (
          <Stack align="center" py="xl" gap={4}>
            <Text fw={500}>Nothing to review here</Text>
            <Text size="sm" c="dimmed">
              No employees currently fall into this category.
            </Text>
          </Stack>
        ) : (
          <Table.ScrollContainer minWidth={900}>
            <Table highlightOnHover striped>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Employee</Table.Th>
                  <Table.Th>Department</Table.Th>
                  <Table.Th>Level</Table.Th>
                  <Table.Th>Country</Table.Th>
                  <Table.Th ta="right">Current salary</Table.Th>
                  {tab === "stale" ? (
                    <>
                      <Table.Th ta="right">Last change</Table.Th>
                      <Table.Th ta="right">Months</Table.Th>
                    </>
                  ) : (
                    <>
                      <Table.Th ta="right">Band</Table.Th>
                      <Table.Th ta="right">Compa-ratio</Table.Th>
                      <Table.Th ta="right">Gap</Table.Th>
                    </>
                  )}
                </Table.Tr>
              </Table.Thead>

              <Table.Tbody>
                {active.findings.map((finding) => (
                  <Table.Tr key={`${finding.employee_id}-${tab}`}>
                    <Table.Td>
                      <Anchor component={Link} to={`/employees/${finding.employee_id}`} fw={500}>
                        {finding.full_name}
                      </Anchor>
                      <Text size="xs" c="dimmed">
                        {finding.employee_code}
                      </Text>
                    </Table.Td>
                    <Table.Td>{finding.department}</Table.Td>
                    <Table.Td>{finding.job_level}</Table.Td>
                    <Table.Td>{finding.country_code}</Table.Td>
                    <Table.Td className="numeric">
                      {formatMoney(finding.amount_cents, finding.currency)}
                    </Table.Td>

                    {tab === "stale" ? (
                      <>
                        <Table.Td className="numeric">
                          {formatDate(finding.effective_from)}
                        </Table.Td>
                        <Table.Td className="numeric">
                          <Text
                            fw={500}
                            c={finding.months_since_change >= 36 ? "orange" : undefined}
                          >
                            {finding.months_since_change}
                          </Text>
                        </Table.Td>
                      </>
                    ) : (
                      <>
                        <Table.Td className="numeric">
                          <Text size="xs" c="dimmed">
                            {formatMoney(finding.band_min_cents, finding.currency)} –{" "}
                            {formatMoney(finding.band_max_cents, finding.currency)}
                          </Text>
                        </Table.Td>
                        <Table.Td className="numeric">
                          {formatRatio(finding.compa_ratio)}
                        </Table.Td>
                        {/* The gap in money, not just a ratio. "12% under"
                            is a statistic; "8,400 short" is a budget line,
                            and the second is what gets a raise approved. */}
                        <Table.Td className="numeric">
                          <Group gap={4} justify="flex-end" wrap="nowrap">
                            <Badge
                              size="sm"
                              variant="light"
                              color={tab === "below" ? "red" : "orange"}
                            >
                              {tab === "below" ? "under" : "over"}
                            </Badge>
                            <Text size="sm">
                              {formatMoney(finding.shortfall_cents, finding.currency)}
                            </Text>
                          </Group>
                        </Table.Td>
                      </>
                    )}
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Card>
    </Stack>
  );
}
