import { Link, useParams } from "react-router-dom";
import {
  Alert,
  Anchor,
  Badge,
  Card,
  Center,
  Grid,
  Group,
  Loader,
  Stack,
  Table,
  Text,
  Timeline,
  Title,
} from "@mantine/core";
import { useEmployee } from "../hooks/useApi";
import { BandIndicator } from "../components/BandIndicator";
import { SalaryForm } from "../components/SalaryForm";
import { formatDate, formatMoney, humanise } from "../lib/money";

export function EmployeePage() {
  // useParams reads :id out of the URL defined in App.tsx.
  const { id } = useParams<{ id: string }>();
  const { data: employee, isLoading, isError, error } = useEmployee(id);

  if (isLoading) {
    return (
      <Center py="xl">
        <Loader />
      </Center>
    );
  }

  if (isError || !employee) {
    return (
      <Alert color="red" role="alert">
        {(error as Error)?.message ?? "Employee not found."}
      </Alert>
    );
  }

  const salary = employee.current_salary;

  return (
    <Stack>
      <div>
        <Anchor component={Link} to="/employees" size="sm">
          ← Back to employees
        </Anchor>
        <Group justify="space-between" align="flex-start" mt="xs">
          <div>
            <Title order={2}>{employee.full_name}</Title>
            <Text c="dimmed">
              {employee.employee_code} · {employee.job_level.name} ·{" "}
              {employee.department.name} · {employee.country_code}
            </Text>
          </div>
          <Badge
            size="lg"
            variant="light"
            color={employee.status === "active" ? "teal" : "gray"}
          >
            {humanise(employee.status)}
          </Badge>
        </Group>
      </div>

      <Grid>
        <Grid.Col span={{ base: 12, md: 7 }}>
          <Stack>
            <Card withBorder padding="lg">
              <Stack gap="md">
                <Group justify="space-between" align="flex-start">
                  <div>
                    <Text size="sm" c="dimmed">
                      Current salary
                    </Text>
                    <Title order={3}>
                      {salary ? formatMoney(salary.amount_cents, salary.currency) : "—"}
                    </Title>
                    {salary && salary.currency !== "USD" && salary.amount_base_cents !== null && (
                      <Text size="sm" c="dimmed">
                        {formatMoney(salary.amount_base_cents, "USD")} at the reference rate
                      </Text>
                    )}
                  </div>

                  {employee.months_since_last_change !== null && (
                    <div style={{ textAlign: "right" }}>
                      <Text size="sm" c="dimmed">
                        Last changed
                      </Text>
                      <Text
                        fw={500}
                        c={employee.months_since_last_change >= 18 ? "orange" : undefined}
                      >
                        {employee.months_since_last_change} months ago
                      </Text>
                    </div>
                  )}
                </Group>

                {/* The whole point of pay bands: not what we pay, but
                    whether it is the right amount for this level in this
                    country. */}
                {employee.pay_band && employee.band_position && salary ? (
                  <BandIndicator
                    band={employee.pay_band}
                    amountCents={salary.amount_cents}
                    position={employee.band_position}
                  />
                ) : (
                  <Text size="sm" c="dimmed">
                    No pay band is defined for {employee.job_level.name} in{" "}
                    {employee.country_code}, so this salary cannot be compared to one.
                  </Text>
                )}
              </Stack>
            </Card>

            <Card withBorder padding="lg">
              <Title order={4} mb="md">
                Salary history
              </Title>

              {/* Newest first. The current figure is what someone opening
                  this page is looking for; history reads backwards from it. */}
              <Timeline bulletSize={14} lineWidth={2}>
                {employee.salaries.map((entry) => (
                  <Timeline.Item
                    key={entry.id}
                    title={formatMoney(entry.amount_cents, entry.currency)}
                    color={entry.current ? "teal" : "gray"}
                  >
                    <Text size="sm" c="dimmed">
                      {humanise(entry.change_reason)} · from {formatDate(entry.effective_from)}
                      {entry.effective_to ? ` to ${formatDate(entry.effective_to)}` : " (current)"}
                    </Text>
                  </Timeline.Item>
                ))}
              </Timeline>

              {employee.salaries.length === 0 && (
                <Text size="sm" c="dimmed">
                  No salary has been recorded for this employee yet.
                </Text>
              )}
            </Card>
          </Stack>
        </Grid.Col>

        <Grid.Col span={{ base: 12, md: 5 }}>
          <Stack>
            <Card withBorder padding="lg">
              <Title order={4} mb="md">
                Record a salary change
              </Title>
              <SalaryForm
                employeeId={employee.id}
                currency={salary?.currency ?? employee.pay_band?.currency ?? "USD"}
                currentAmountCents={salary?.amount_cents ?? null}
              />
            </Card>

            <Card withBorder padding="lg">
              <Title order={4} mb="md">
                Details
              </Title>
              <Table variant="vertical" layout="fixed">
                <Table.Tbody>
                  <Table.Tr>
                    <Table.Th w={140}>Email</Table.Th>
                    <Table.Td>{employee.email}</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Th>Employment</Table.Th>
                    <Table.Td>{humanise(employee.employment_type)}</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Th>Hired</Table.Th>
                    <Table.Td>{formatDate(employee.hired_on)}</Table.Td>
                  </Table.Tr>
                  {employee.terminated_on && (
                    <Table.Tr>
                      <Table.Th>Left</Table.Th>
                      <Table.Td>{formatDate(employee.terminated_on)}</Table.Td>
                    </Table.Tr>
                  )}
                  <Table.Tr>
                    <Table.Th>Manager</Table.Th>
                    <Table.Td>
                      {employee.manager ? (
                        <Anchor component={Link} to={`/employees/${employee.manager.id}`}>
                          {employee.manager.full_name}
                        </Anchor>
                      ) : (
                        <Text c="dimmed">—</Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                </Table.Tbody>
              </Table>
            </Card>
          </Stack>
        </Grid.Col>
      </Grid>
    </Stack>
  );
}
