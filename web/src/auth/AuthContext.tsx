// Who is signed in, available anywhere in the tree.
//
// React Context is plain React: createContext makes a value available to
// descendants without passing it through every component as props, and
// useContext reads it. Nothing library-specific is happening here.
//
// The session itself lives in an http-only cookie that JavaScript cannot
// read. So "am I signed in?" cannot be answered locally — it is answered by
// asking the server, which is what the /me request below does on startup.

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { ApiError, apiDelete, apiGet, apiPost } from "../api/client";
import type { User } from "../api/types";

interface AuthValue {
  user: User | null;
  /** True until the initial /me request settles, so guards can wait. */
  isLoading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Runs once on mount. A 401 here is the normal "not signed in" answer,
  // not an error worth surfacing.
  useEffect(() => {
    let cancelled = false;

    apiGet<{ user: User }>("/me")
      .then((response) => {
        if (!cancelled) setUser(response.user);
      })
      .catch(() => {
        if (!cancelled) setUser(null);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    // Cleanup: if the component unmounts before the request finishes,
    // do not call setState on something that is gone.
    return () => {
      cancelled = true;
    };
  }, []);

  async function signIn(email: string, password: string) {
    const response = await apiPost<{ user: User }>("/session", {
      email_address: email,
      password,
    });

    setUser(response.user);
  }

  async function signOut() {
    try {
      await apiDelete("/session");
    } catch (error) {
      // Already signed out server-side is a success from here.
      if (!(error instanceof ApiError && error.isUnauthenticated)) throw error;
    } finally {
      setUser(null);
    }
  }

  return (
    <AuthContext.Provider value={{ user, isLoading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);

  // Catches the mistake of using this hook outside the provider, which
  // would otherwise fail later with a confusing "cannot read property of
  // null".
  if (!value) throw new Error("useAuth must be used inside an AuthProvider");

  return value;
}
