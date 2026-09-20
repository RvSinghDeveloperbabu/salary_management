// Wraps the routes that need a signed-in user.
//
// This is a guard in the UI only. It hides screens; it does not protect
// data. Every API endpoint independently returns 401 without a valid
// session, which is the protection that actually matters — someone can
// always call the API directly.

import { Center, Loader } from "@mantine/core";
import { Navigate, useLocation } from "react-router-dom";
import type { ReactNode } from "react";
import { useAuth } from "./AuthContext";

export function RequireAuth({ children }: { children: ReactNode }) {
  const { user, isLoading } = useAuth();
  const location = useLocation();

  // Wait for the initial /me request. Redirecting during this window would
  // bounce a signed-in user to the login page on every refresh.
  if (isLoading) {
    return (
      <Center h="100vh">
        <Loader />
      </Center>
    );
  }

  if (!user) {
    // `state` remembers where they were heading, so signing in returns them
    // there instead of dumping them on the dashboard.
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  return <>{children}</>;
}
