import { Card, Group, Skeleton, Text, Title, Tooltip } from "@mantine/core";
import type { ReactNode } from "react";

interface Props {
  label: string;
  value: ReactNode;
  hint?: string;
  /** Shown on hover where the headline is rounded or needs qualifying. */
  detail?: string;
  isLoading?: boolean;
  color?: string;
}

export function StatCard({ label, value, hint, detail, isLoading, color }: Props) {
  const headline = (
    <Title order={2} c={color}>
      {value}
    </Title>
  );

  return (
    <Card withBorder padding="lg" h="100%">
      <Text size="sm" c="dimmed" fw={500}>
        {label}
      </Text>

      {isLoading ? (
        <Skeleton height={32} mt={8} width="60%" />
      ) : (
        <Group gap="xs" mt={4} align="baseline">
          {detail ? (
            <Tooltip label={detail} withArrow>
              {headline}
            </Tooltip>
          ) : (
            headline
          )}
        </Group>
      )}

      {hint && (
        <Text size="xs" c="dimmed" mt={4}>
          {hint}
        </Text>
      )}
    </Card>
  );
}
