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

/** "market_adjustment" -> "Market adjustment" */
export function humanise(value: string | null | undefined): string {
  if (!value) return "—";

  const spaced = value.replace(/_/g, " ");

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}
