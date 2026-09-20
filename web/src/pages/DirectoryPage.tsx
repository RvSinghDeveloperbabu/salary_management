import { useState } from "react";
import { Link } from "react-router-dom";
import {
  Alert,
  Anchor,
  Badge,
  Card,
  Group,
  Loader,
  Pagination,
  Stack,
  Table,
  Text,
  Title,
  UnstyledButton,
} from "@mantine/core";
import { useDebounced } from "../hooks/useDebounced";
import { useEmployees, useReference } from "../hooks/useApi";
import { DirectoryFilters, EMPTY_FILTERS, type FilterState } from "../components/DirectoryFilters";
import { formatDate, formatMoney, humanise } from "../lib/money";

const PER_PAGE = 25;

// Columns are a plain array of objects: a label, and whether the API will
// sort by it. `sortKey` values must exist in the server's allow-list, or
// the request comes back 400 — which is that allow-list working.
const COLUMNS: { label: string; sortKey?: string; numeric?: boolean }[] = [
  { label: "Name", sortKey: "name" },
  { label: "Code" },
  { label: "Department", sortKey: "department" },
  { label: "Level", sortKey: "level" },
  { label: "Country" },
  { label: "Current salary", sortKey: "salary", numeric: true },
  { label: "Hired", sortKey: "hired_on" },
  { label: "Status" },
];

export function DirectoryPage() {
  const [filters, setFilters] = useState<FilterState>(EMPTY_FILTERS);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState("name");
  const [direction, setDirection] = useState<"asc" | "desc">("asc");

  // Only the search term is debounced. Choosing from a dropdown is a
  // deliberate single action and should take effect at once.
  const debouncedQuery = useDebounced(filters.q, 300);

  const { data: reference } = useReference();

  const query = useEmployees({
    ...filters,
    q: debouncedQuery,
    sort,
    direction,
    page,
    per_page: PER_PAGE,
  });

  const employees = query.data?.employees ?? [];
  const pagination = query.data?.pagination;

  function handleFilterChange(next: FilterState) {
    setFilters(next);
    // Page 4 of the previous result set is meaningless against a new one,
    // and is usually out of range entirely.
    setPage(1);
  }

  function toggleSort(sortKey: string) {
    if (sort === sortKey) {
      setDirection((current) => (current === "asc" ? "desc" : "asc"));
    } else {
      setSort(sortKey);
      setDirection("asc");
    }
    setPage(1);
  }

  return (
    <Stack>
      <Group justify="space-between" align="flex-end">
        <div>
          <Title order={2}>Employees</Title>
          {pagination && (
            <Text size="sm" c="dimmed">
              {pagination.total_count.toLocaleString()} matching
            </Text>
          )}
        </div>
        {query.isFetching && <Loader size="sm" />}
      </Group>

      <Card withBorder padding="md">
        <DirectoryFilters
          value={filters}
          onChange={handleFilterChange}
          reference={reference}
          isLoading={!reference}
        />
      </Card>

      {query.isError && (
        <Alert color="red" role="alert">
          {(query.error as Error).message}
        </Alert>
      )}

      <Card withBorder padding={0}>
        <Table.ScrollContainer minWidth={900}>
          <Table highlightOnHover striped>
            <Table.Thead>
              <Table.Tr>
                {COLUMNS.map((column) => (
                  <Table.Th key={column.label}>
                    {column.sortKey ? (
                      <UnstyledButton
                        onClick={() => toggleSort(column.sortKey!)}
                        aria-label={`Sort by ${column.label}`}
                      >
                        <Group gap={4} wrap="nowrap">
                          <Text size="sm" fw={600}>
                            {column.label}
                          </Text>
                          <Text size="xs" c={sort === column.sortKey ? "blue" : "dimmed"}>
                            {sort === column.sortKey ? (direction === "asc" ? "▲" : "▼") : "⇅"}
                          </Text>
                        </Group>
                      </UnstyledButton>
                    ) : (
                      <Text size="sm" fw={600}>
                        {column.label}
                      </Text>
                    )}
                  </Table.Th>
                ))}
              </Table.Tr>
            </Table.Thead>

            <Table.Tbody>
              {query.isLoading && (
                <Table.Tr>
                  <Table.Td colSpan={COLUMNS.length}>
                    <Group justify="center" py="xl">
                      <Loader size="sm" />
                      <Text c="dimmed">Loading employees…</Text>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              )}

              {!query.isLoading && employees.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={COLUMNS.length}>
                    <Stack align="center" py="xl" gap={4}>
                      <Text fw={500}>No employees match these filters</Text>
                      <Text size="sm" c="dimmed">
                        Try clearing the search term or widening the filters.
                      </Text>
                    </Stack>
                  </Table.Td>
                </Table.Tr>
              )}

              {employees.map((employee) => (
                <Table.Tr key={employee.id}>
                  <Table.Td>
                    <Anchor component={Link} to={`/employees/${employee.id}`} fw={500}>
                      {employee.full_name}
                    </Anchor>
                  </Table.Td>

                  <Table.Td>
                    <Text size="sm" c="dimmed">
                      {employee.employee_code}
                    </Text>
                  </Table.Td>

                  <Table.Td>{employee.department.name}</Table.Td>
                  <Table.Td>{employee.job_level.name}</Table.Td>
                  <Table.Td>{employee.country_code}</Table.Td>

                  <Table.Td className="numeric">
                    {employee.current_salary ? (
                      <>
                        <Text size="sm">
                          {formatMoney(
                            employee.current_salary.amount_cents,
                            employee.current_salary.currency,
                          )}
                        </Text>
                        {/* Local currency is what the person is paid; the USD
                            figure is what makes them comparable to everyone
                            else, so both are shown rather than one. */}
                        {employee.current_salary.currency !== "USD" &&
                          employee.current_salary.amount_base_cents !== null && (
                            <Text size="xs" c="dimmed">
                              {formatMoney(employee.current_salary.amount_base_cents, "USD")}
                            </Text>
                          )}
                      </>
                    ) : (
                      <Text c="dimmed">—</Text>
                    )}
                  </Table.Td>

                  <Table.Td>
                    <Text size="sm">{formatDate(employee.hired_on)}</Text>
                  </Table.Td>

                  <Table.Td>
                    <Badge
                      variant="light"
                      color={employee.status === "active" ? "teal" : "gray"}
                    >
                      {humanise(employee.status)}
                    </Badge>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Card>

      {pagination && pagination.total_pages > 1 && (
        <Group justify="center">
          <Pagination
            total={pagination.total_pages}
            value={pagination.page}
            onChange={setPage}
            siblings={1}
          />
        </Group>
      )}
    </Stack>
  );
}
