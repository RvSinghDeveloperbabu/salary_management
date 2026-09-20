import { useEffect, useState } from "react";

/**
 * Returns `value` only after it has stopped changing for `delay` ms.
 *
 * Used for the directory search box. Without it, typing "Lovelace" fires
 * eight requests against a 10,000-row table and the answers can arrive out
 * of order, so the results briefly show matches for "Lovelac".
 *
 * Plain React: a timer started on each change, and a cleanup that cancels
 * the previous one. The cleanup is what makes it a debounce rather than
 * just a delay.
 */
export function useDebounced<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);

    return () => clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}
