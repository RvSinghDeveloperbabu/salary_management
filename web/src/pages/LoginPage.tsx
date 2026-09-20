import { useState, type FormEvent } from "react";
import { Alert, Button, Card, Center, PasswordInput, Stack, Text, TextInput, Title } from "@mantine/core";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { ApiError } from "../api/client";
import { useAuth } from "../auth/AuthContext";

export function LoginPage() {
  const { user, signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Where they were trying to go before being redirected here.
  const destination = (location.state as { from?: string } | null)?.from ?? "/";

  if (user) return <Navigate to={destination} replace />;

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      await signIn(email, password);
      navigate(destination, { replace: true });
    } catch (caught) {
      // The server deliberately does not say whether the address or the
      // password was wrong, so neither does this.
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Could not sign in. Please try again.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <Center h="100vh" bg="var(--mantine-color-gray-0)">
      <Card withBorder shadow="sm" padding="xl" radius="md" w={400}>
        <form onSubmit={handleSubmit}>
          <Stack>
            <div>
              <Title order={3}>Salary Management</Title>
              <Text size="sm" c="dimmed">
                Sign in to view compensation data.
              </Text>
            </div>

            {error && (
              <Alert color="red" role="alert">
                {error}
              </Alert>
            )}

            <TextInput
              label="Email address"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.currentTarget.value)}
              autoComplete="username"
              required
            />

            <PasswordInput
              label="Password"
              value={password}
              onChange={(event) => setPassword(event.currentTarget.value)}
              autoComplete="current-password"
              required
            />

            <Button type="submit" loading={isSubmitting} fullWidth>
              Sign in
            </Button>
          </Stack>
        </form>
      </Card>
    </Center>
  );
}
