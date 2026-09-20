import { Box, Group, Stack, Text, Tooltip } from "@mantine/core";
import type { BandPosition, PayBand } from "../api/types";
import { formatMoney, formatRatio } from "../lib/money";

interface Props {
  band: PayBand;
  amountCents: number;
  position: BandPosition;
}

const COLOURS: Record<BandPosition["position"], string> = {
  below: "var(--mantine-color-red-6)",
  within: "var(--mantine-color-teal-6)",
  above: "var(--mantine-color-orange-6)",
};

const LABELS: Record<BandPosition["position"], string> = {
  below: "Below band minimum",
  within: "Within band",
  above: "Above band maximum",
};

/**
 * Where this salary sits in its pay band, drawn as a bar.
 *
 * A compa-ratio of 0.82 is precise but hard to feel. Seeing the marker sit
 * outside the shaded range communicates the same fact instantly, which is
 * the difference between a number on a screen and a decision.
 */
export function BandIndicator({ band, amountCents, position }: Props) {
  // The axis runs a little wider than the band itself so a salary outside
  // it still lands on the chart instead of being clamped to the edge.
  const padding = (band.max_cents - band.min_cents) * 0.25;
  const axisMin = Math.min(band.min_cents - padding, amountCents);
  const axisMax = Math.max(band.max_cents + padding, amountCents);
  const span = axisMax - axisMin || 1;

  const toPercent = (value: number) => ((value - axisMin) / span) * 100;

  const bandLeft = toPercent(band.min_cents);
  const bandWidth = toPercent(band.max_cents) - bandLeft;
  const markerLeft = toPercent(amountCents);
  const midLeft = toPercent(band.mid_cents);

  return (
    <Stack gap={6}>
      <Group justify="space-between">
        <Text size="sm" fw={500} c={COLOURS[position.position]}>
          {LABELS[position.position]}
        </Text>
        <Text size="sm" c="dimmed">
          Compa-ratio {formatRatio(position.compa_ratio)}
        </Text>
      </Group>

      <Box pos="relative" h={28}>
        {/* Full axis */}
        <Box
          pos="absolute"
          top={11}
          left={0}
          right={0}
          h={6}
          style={{ background: "var(--mantine-color-gray-2)", borderRadius: 3 }}
        />

        {/* The band itself */}
        <Box
          pos="absolute"
          top={11}
          h={6}
          style={{
            left: `${bandLeft}%`,
            width: `${bandWidth}%`,
            background: "var(--mantine-color-blue-1)",
            borderRadius: 3,
          }}
        />

        {/* Midpoint */}
        <Box
          pos="absolute"
          top={7}
          h={14}
          w={2}
          style={{ left: `${midLeft}%`, background: "var(--mantine-color-blue-4)" }}
        />

        {/* This employee */}
        <Tooltip label={formatMoney(amountCents, band.currency)} withArrow>
          <Box
            pos="absolute"
            top={4}
            h={20}
            w={4}
            style={{
              left: `calc(${markerLeft}% - 2px)`,
              background: COLOURS[position.position],
              borderRadius: 2,
            }}
          />
        </Tooltip>
      </Box>

      <Group justify="space-between">
        <Text size="xs" c="dimmed">
          {formatMoney(band.min_cents, band.currency)}
        </Text>
        <Text size="xs" c="dimmed">
          mid {formatMoney(band.mid_cents, band.currency)}
        </Text>
        <Text size="xs" c="dimmed">
          {formatMoney(band.max_cents, band.currency)}
        </Text>
      </Group>
    </Stack>
  );
}
