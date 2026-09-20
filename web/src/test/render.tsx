// Renders a component inside the same providers main.tsx uses.
//
// Without them, anything touching Mantine, TanStack Query or React Router
// throws on render — which would look like a failing component rather than
// a missing provider.

import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { render, type RenderOptions } from "@testing-library/react";
import type { ReactElement, ReactNode } from "react";

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // A test asserting an error state should not wait through retries
        // to see it.
        retry: false,
        // Every test starts from a cold cache, so one test cannot pass
        // because a previous one populated it.
        staleTime: 0,
        gcTime: 0,
      },
      mutations: { retry: false },
    },
  });
}

interface Options extends Omit<RenderOptions, "wrapper"> {
  /** Initial URL, for components that read route params. */
  route?: string;
}

export function renderWithProviders(ui: ReactElement, { route = "/", ...options }: Options = {}) {
  const queryClient = createTestQueryClient();

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      // env="test" turns off Mantine's transitions and portals. Without it
      // a dropdown's options never finish animating into the DOM under
      // jsdom, so the test sees an empty listbox and fails for a reason
      // that has nothing to do with the component.
      <MantineProvider env="test">
        <QueryClientProvider client={queryClient}>
          <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
        </QueryClientProvider>
      </MantineProvider>
    );
  }

  return { queryClient, ...render(ui, { wrapper: Wrapper, ...options }) };
}
