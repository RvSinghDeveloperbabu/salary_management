import { Button, Group, Select, TextInput } from "@mantine/core";
import type { Reference } from "../api/types";
import { humanise } from "../lib/money";

export interface FilterState {
  q: string;
  department_id: string;
  job_level_id: string;
  country_code: string;
  status: string;
}

export const EMPTY_FILTERS: FilterState = {
  q: "",
  department_id: "",
  job_level_id: "",
  country_code: "",
  // Active by default. A directory that opens showing leavers alongside
  // current staff answers a different question from the one being asked.
  status: "active",
};

interface Props {
  value: FilterState;
  onChange: (next: FilterState) => void;
  reference?: Reference;
  isLoading?: boolean;
}

/**
 * The filter bar. Options come from /reference rather than being hard-coded,
 * so the country list can never offer somewhere with nobody in it, and the
 * app cannot drift out of step with the database.
 */
export function DirectoryFilters({ value, onChange, reference, isLoading }: Props) {
  // Mantine's Select wants {value,label} pairs and uses "" for "cleared",
  // which matches the API's treatment of a blank filter as "no filter".
  function set<K extends keyof FilterState>(key: K, next: string) {
    onChange({ ...value, [key]: next });
  }

  const hasFilters =
    value.q !== "" ||
    value.department_id !== "" ||
    value.job_level_id !== "" ||
    value.country_code !== "" ||
    value.status !== "active";

  return (
    <Group align="flex-end" gap="sm" wrap="wrap">
      <TextInput
        label="Search"
        placeholder="Name, email or employee code"
        value={value.q}
        onChange={(event) => set("q", event.currentTarget.value)}
        w={260}
        aria-label="Search employees"
      />

      <Select
        label="Department"
        placeholder="All"
        clearable
        disabled={isLoading}
        value={value.department_id || null}
        onChange={(next) => set("department_id", next ?? "")}
        data={(reference?.departments ?? []).map((d) => ({
          value: String(d.id),
          label: d.name,
        }))}
        w={180}
      />

      <Select
        label="Level"
        placeholder="All"
        clearable
        disabled={isLoading}
        value={value.job_level_id || null}
        onChange={(next) => set("job_level_id", next ?? "")}
        data={(reference?.job_levels ?? []).map((l) => ({
          value: String(l.id),
          label: l.name,
        }))}
        w={120}
      />

      <Select
        label="Country"
        placeholder="All"
        clearable
        disabled={isLoading}
        value={value.country_code || null}
        onChange={(next) => set("country_code", next ?? "")}
        data={(reference?.countries ?? []).map((c) => ({ value: c, label: c }))}
        w={120}
      />

      <Select
        label="Status"
        placeholder="All"
        clearable
        disabled={isLoading}
        value={value.status || null}
        onChange={(next) => set("status", next ?? "")}
        data={(reference?.statuses ?? []).map((s) => ({ value: s, label: humanise(s) }))}
        w={140}
      />

      {hasFilters && (
        <Button variant="subtle" onClick={() => onChange(EMPTY_FILTERS)}>
          Reset
        </Button>
      )}
    </Group>
  );
}
