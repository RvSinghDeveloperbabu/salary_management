// The frame every signed-in screen renders inside: header, navigation,
// and an <Outlet> where the routed page appears.
//
// <Outlet> is React Router's placeholder for "whichever child route
// matched". It is what lets the header and nav stay put while only the
// page content changes.

import { AppShell, Burger, Button, Group, NavLink, Text, Title } from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

const NAV_ITEMS = [
  { label: "Dashboard", to: "/" },
  { label: "Employees", to: "/employees" },
  { label: "Pay review", to: "/outliers" },
];

export function AppLayout() {
  const [opened, { toggle }] = useDisclosure();
  const { user, signOut } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  async function handleSignOut() {
    await signOut();
    navigate("/login", { replace: true });
  }

  return (
    <AppShell
      header={{ height: 60 }}
      navbar={{ width: 220, breakpoint: "sm", collapsed: { mobile: !opened } }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Group>
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" />
            <Title order={4}>Salary Management</Title>
          </Group>

          <Group gap="sm">
            <Text size="sm" c="dimmed" visibleFrom="sm">
              {user?.email_address}
            </Text>
            <Button variant="subtle" size="compact-sm" onClick={handleSignOut}>
              Sign out
            </Button>
          </Group>
        </Group>
      </AppShell.Header>

      <AppShell.Navbar p="sm">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            component={Link}
            to={item.to}
            label={item.label}
            // Exact match for the dashboard, prefix match for the rest, so
            // /employees/42 still highlights "Employees".
            active={
              item.to === "/"
                ? location.pathname === "/"
                : location.pathname.startsWith(item.to)
            }
          />
        ))}
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
