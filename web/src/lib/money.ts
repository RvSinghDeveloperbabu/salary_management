// Money arrives from the API as integer cents plus a currency code, and it
// stays that way until the moment it is shown to a person. These helpers
// are the only place a number becomes a string.
//
// Nothing here ever feeds a formatted value back into arithmetic.

/** 1_234_567 + "USD" -> "$12,345.67" */
export function formatMoney(cents: number | null | undefined, currency: string): string {
  if (cents === null || cents === undefined) return "—";

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(cents / 100);
}

/**
 * Large totals, shortened for dashboard tiles: 4_210_000_000 -> "$42.1M".
 * Full precision is still available on hover in the charts.
 */
export function formatCompactMoney(cents: number | null | undefined, currency: string): string {
  if (cents === null || cents === undefined) return "—";

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(cents / 100);
}

/** 0.87 -> "0.87" ; null -> "—" */
export function formatRatio(ratio: number | null | undefined): string {
  if (ratio === null || ratio === undefined) return "—";

  return ratio.toFixed(2);
}

/** "2026-03-14" -> "14 Mar 2026". Dates arrive as ISO strings. */
export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";

  return new Date(`${iso}T00:00:00`).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * Parses what someone typed into integer cents. Returns null if it is not
 * a valid amount.
 *
 * Deliberately not `parseFloat(input) * 100`. That is the classic way to
 * lose a penny: 19.99 * 100 is 1998.9999999999998 in binary floating point,
 * which truncates to 1998 — one cent short, silently, on exactly the values
 * people type most. Splitting the string and doing integer arithmetic
 * cannot drift.
 */
export function parseAmountToCents(input: string): number | null {
  const cleaned = input.trim().replace(/[\s,]/g, "");

  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;

  const [whole, fraction = ""] = cleaned.split(".");

  return Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
}

/** Integer cents back into an editable string: 1_234_500 -> "12345.00" */
export function centsToInput(cents: number): string {
  return (cents / 100).toFixed(2);
}

/** "market_adjustment" -> "Market adjustment" */
export function humanise(value: string | null | undefined): string {
  if (!value) return "—";

  const spaced = value.replace(/_/g, " ");

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}
