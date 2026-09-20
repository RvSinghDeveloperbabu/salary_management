// The route table.
//
// Routes nested inside <Route element={<AppLayout />}> render into that
// layout's <Outlet>, so the header and navigation are declared once rather
// than repeated on every page.

import { Route, Routes } from "react-router-dom";
import { AppLayout } from "./components/AppLayout";
import { RequireAuth } from "./auth/RequireAuth";
import { LoginPage } from "./pages/LoginPage";
import { DashboardPage } from "./pages/DashboardPage";
import { DirectoryPage } from "./pages/DirectoryPage";
import { EmployeePage } from "./pages/EmployeePage";
import { OutliersPage } from "./pages/OutliersPage";

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route
        element={
          <RequireAuth>
            <AppLayout />
          </RequireAuth>
        }
      >
        <Route path="/" element={<DashboardPage />} />
        <Route path="/employees" element={<DirectoryPage />} />
        <Route path="/employees/:id" element={<EmployeePage />} />
        <Route path="/outliers" element={<OutliersPage />} />
      </Route>

      {/* Anything unrecognised goes to the dashboard rather than a blank screen. */}
      <Route path="*" element={<DashboardPage />} />
    </Routes>
  );
}
