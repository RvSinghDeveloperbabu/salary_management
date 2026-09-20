// Application entry point. Four providers wrap the app, each supplying
// something the whole tree needs:
//
//   MantineProvider   theme and styling for Mantine components
//   QueryClientProvider  the TanStack Query cache
//   BrowserRouter     URL-based routing
//   AuthProvider      who is signed in
//
// Order matters only in that AuthProvider uses the API and Router, so it
// sits inside both.

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router-dom";

import "@mantine/core/styles.css";
import "./index.css";

import { App } from "./App";
import { AuthProvider } from "./auth/AuthContext";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Analytics are cached server-side against a data watermark, so the
      // browser refetching on every window focus would be wasted work.
      refetchOnWindowFocus: false,
      // A 401 means the session ended; retrying cannot fix that. Retry
      // anything else once, in case it was a blip.
      retry: (failureCount, error) => {
        const status = (error as { status?: number }).status;
        if (status === 401 || status === 400 || status === 404) return false;
        return failureCount < 1;
      },
      staleTime: 30_000,
    },
  },
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <MantineProvider defaultColorScheme="light">
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <AuthProvider>
            <App />
          </AuthProvider>
        </BrowserRouter>
      </QueryClientProvider>
    </MantineProvider>
  </StrictMode>,
);
