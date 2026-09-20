import { useState, type FormEvent } from "react";
import { Alert, Button, Group, Select, Stack, Text, TextInput } from "@mantine/core";
import { ApiError } from "../api/client";
import { useRecordSalary, useReference } from "../hooks/useApi";
import { formatMoney, humanise, parseAmountToCents } from "../lib/money";

interface Props {
  employeeId: number;
  currency: string;
  currentAmountCents: number | null;
  onRecorded?: () => void;
}

/** Today in YYYY-MM-DD, which is what the API expects and the maximum it accepts. */
function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Records a salary change.
 *
 * Every submission is an INSERT: the API has no route that edits an
 * existing salary, because the history is append-only. Correcting a mistake
 * means recording a new row with reason "correction", which is why that is
 * one of the options rather than something hidden.
 */
export function SalaryForm({ employeeId, currency, currentAmountCents, onRecorded }: Props) {
  const { data: reference } = useReference();
  const mutation = useRecordSalary();

  const [amount, setAmount] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState(todayIso());
  const [reason, setReason] = useState<string>("merit");
  const [amountError, setAmountError] = useState<string | null>(null);

  const parsedCents = parseAmountToCents(amount);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setAmountError(null);

    if (parsedCents === null || parsedCents <= 0) {
      setAmountError("Enter an amount, for example 95000 or 95000.50");
      return;
    }

    try {
      await mutation.mutateAsync({
        employeeId,
        amount_cents: parsedCents,
        currency,
        effective_from: effectiveFrom,
        change_reason: reason,
      });

      setAmount("");
      onRecorded?.();
    } catch {
      // Rendered from mutation.error below; nothing to do here.
    }
  }

  const error = mutation.error instanceof ApiError ? mutation.error : null;

  return (
    <form onSubmit={handleSubmit}>
      <Stack gap="sm">
        {error && (
          <Alert color="red" role="alert">
            {error.message}
          </Alert>
        )}

        <Group align="flex-start" grow>
          <TextInput
            label={`New salary (${currency})`}
            placeholder="95000"
            value={amount}
            onChange={(event) => setAmount(event.currentTarget.value)}
            error={amountError ?? error?.messageFor("amount_cents")}
            inputMode="decimal"
            required
          />

          <TextInput
            label="Effective from"
            type="date"
            value={effectiveFrom}
            onChange={(event) => setEffectiveFrom(event.currentTarget.value)}
            // Future-dated changes are rejected by the API, so the picker
            // does not offer them. The server still enforces it.
            max={todayIso()}
            error={error?.messageFor("effective_from")}
            required
          />
        </Group>

        <Select
          label="Reason"
          value={reason}
          onChange={(next) => setReason(next ?? "merit")}
          data={(reference?.change_reasons ?? []).map((value) => ({
            value,
            label: humanise(value),
          }))}
          required
        />

        {/* Immediate feedback on what was typed, so a mistyped figure is
            caught before it becomes a permanent history row. */}
        {parsedCents !== null && parsedCents > 0 && (
          <Text size="sm" c="dimmed">
            Recording {formatMoney(parsedCents, currency)}
            {currentAmountCents !== null && currentAmountCents > 0 && (
              <>
                {" — "}
                {(((parsedCents - currentAmountCents) / currentAmountCents) * 100).toFixed(1)}%
                {parsedCents >= currentAmountCents ? " increase" : " decrease"}
              </>
            )}
          </Text>
        )}

        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>
            Record change
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
