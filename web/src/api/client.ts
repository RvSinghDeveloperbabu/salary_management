// A thin wrapper over `fetch`. Nothing is hidden: these are the same calls
// you would write by hand, with three shared concerns handled in one place.
//
//   1. Every failure arrives in the same shape, so components never have to
//      guess whether `error` is a string, an object, or a Response.
//   2. Cookies are sent, which is how the session works.
//   3. Query strings skip blank values, so an empty filter does not become
//      `?department_id=` and filter everything out.

import type { ApiErrorBody } from "./types";

const BASE = "/api/v1";

/**
 * Thrown for any non-2xx response. Carries the pieces a component actually
 * needs to react: the HTTP status, the machine-readable code, and per-field
 * validation messages when the server sent them.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, string[]>;

  constructor(status: number, code: string, message: string, details: Record<string, string[]> = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }

  /** 401 means "log in again" rather than "something went wrong". */
  get isUnauthenticated(): boolean {
    return this.status === 401;
  }

  /** The first message for a field, for showing under an input. */
  messageFor(field: string): string | undefined {
    return this.details[field]?.[0];
  }
}

export type QueryValue = string | number | boolean | null | undefined;

function buildPath(path: string, query?: Record<string, QueryValue>): string {
  if (!query) return `${BASE}${path}`;

  const params = new URLSearchParams();

  for (const [key, value] of Object.entries(query)) {
    // Blank means "no filter". Sending an empty value would be a filter
    // that matches nothing.
    if (value === null || value === undefined || value === "") continue;
    params.set(key, String(value));
  }

  const qs = params.toString();
  return qs ? `${BASE}${path}?${qs}` : `${BASE}${path}`;
}

async function request<T>(path: string, init: RequestInit): Promise<T> {
  const response = await fetch(path, {
    // The session cookie is http-only, so JavaScript cannot read or attach
    // it explicitly. "same-origin" tells fetch to send it anyway.
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    ...init,
  });

  if (response.status === 204) return undefined as T;

  const text = await response.text();
  const body = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const envelope = body as ApiErrorBody | null;

    throw new ApiError(
      response.status,
      envelope?.error?.code ?? "unknown",
      envelope?.error?.message ?? `Request failed with status ${response.status}`,
      envelope?.error?.details ?? {},
    );
  }

  return body as T;
}

export function apiGet<T>(path: string, query?: Record<string, QueryValue>): Promise<T> {
  return request<T>(buildPath(path, query), { method: "GET" });
}

export function apiPost<T>(path: string, body?: unknown): Promise<T> {
  return request<T>(buildPath(path), {
    method: "POST",
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export function apiPatch<T>(path: string, body: unknown): Promise<T> {
  return request<T>(buildPath(path), { method: "PATCH", body: JSON.stringify(body) });
}

export function apiDelete<T>(path: string): Promise<T> {
  return request<T>(buildPath(path), { method: "DELETE" });
}
