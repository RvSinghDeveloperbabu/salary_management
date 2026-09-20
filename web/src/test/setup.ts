import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, vi } from "vitest";
import { server } from "./server";

// onUnhandledRequest: "error" makes a request nobody mocked fail loudly.
// Without it, a typo in a URL returns undefined and the test fails much
// later with a confusing message about reading a property of null.
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));

afterEach(() => {
  cleanup();
  // Drops any per-test handler overrides, so one test cannot leak its
  // mocked responses into the next.
  server.resetHandlers();
});

afterAll(() => server.close());

// Mantine components query these at render time and jsdom implements
// neither. Without the stubs, anything using a Mantine layout primitive
// throws before a single assertion runs.
window.matchMedia =
  window.matchMedia ||
  ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }));

class ResizeObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
}

window.ResizeObserver = window.ResizeObserver ?? ResizeObserverStub;

// Recharts measures its container before drawing. jsdom reports zero for
// every dimension, so charts would render empty in tests.
Object.defineProperty(HTMLElement.prototype, "offsetWidth", {
  configurable: true,
  value: 800,
});
Object.defineProperty(HTMLElement.prototype, "offsetHeight", {
  configurable: true,
  value: 400,
});
