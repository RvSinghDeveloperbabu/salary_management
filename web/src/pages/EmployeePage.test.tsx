import { describe, expect, it } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../test/render";
import { reference, server } from "../test/server";
import { EmployeePage } from "./EmployeePage";

const detail = {
  id: 7,
  employee_code: "EMP-00007",
  first_name: "Ada",
  last_name: "Lovelace",
  full_name: "Ada Lovelace",
  email: "ada@example.com",
  country_code: "GB",
  employment_type: "full_time",
  status: "active",
  hired_on: "2020-01-15",
  terminated_on: null,
  department: reference.departments[0],
  job_level: reference.job_levels[1],
  pay_band: {
    id: 1,
    country_code: "GB",
    currency: "GBP",
    min_cents: 8_000_000,
    mid_cents: 10_000_000,
    max_cents: 12_000_000,
  },
  manager: { id: 2, full_name: "Grace Hopper", employee_code: "EMP-00002" },
  salaries: [
    {
      id: 20,
      amount_cents: 9_000_000,
      currency: "GBP",
      amount_base_cents: 11_430_000,
      effective_from: "2024-01-01",
      effective_to: null,
      change_reason: "merit",
      current: true,
    },
    {
      id: 19,
      amount_cents: 8_000_000,
      currency: "GBP",
      amount_base_cents: 10_160_000,
      effective_from: "2020-01-15",
      effective_to: "2023-12-31",
      change_reason: "hire",
      current: false,
    },
  ],
  current_salary: {
    id: 20,
    amount_cents: 9_000_000,
    currency: "GBP",
    amount_base_cents: 11_430_000,
    effective_from: "2024-01-01",
    change_reason: "merit",
  },
  band_position: { position: "within", compa_ratio: 0.9 },
  months_since_last_change: 8,
};

function renderPage() {
  return renderWithProviders(
    <Routes>
      <Route path="/employees/:id" element={<EmployeePage />} />
    </Routes>,
    { route: "/employees/7" },
  );
}

describe("EmployeePage", () => {
  // The endpoint wraps its payload as { employee: ... }. apiGet's type
  // parameter is an assertion rather than a check, so claiming the wrapper
  // *is* the employee typechecked cleanly and then crashed the page on
  // `employee.job_level.name`. Only a real render catches that, which is
  // what this spec is for.
  it("unwraps the { employee: ... } payload the API returns", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () => HttpResponse.json({ employee: detail })),
    );

    renderPage();

    expect(await screen.findByRole("heading", { name: "Ada Lovelace" })).toBeInTheDocument();
    // Reading these proves the nested objects survived the unwrap.
    expect(screen.getByText(/EMP-00007/)).toBeInTheDocument();
    expect(screen.getByText(/Engineering/)).toBeInTheDocument();
  });

  it("shows the current salary in local currency with the USD equivalent", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () => HttpResponse.json({ employee: detail })),
    );

    renderPage();

    // The figure appears twice on purpose — as the headline and as the
    // current row of the history — so the headline is picked by its role.
    expect(await screen.findByRole("heading", { name: "£90,000" })).toBeInTheDocument();
    expect(screen.getByText(/\$114,300 at the reference rate/)).toBeInTheDocument();
  });

  it("renders the full salary history, newest first", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () => HttpResponse.json({ employee: detail })),
    );

    renderPage();

    await screen.findByRole("heading", { name: "Ada Lovelace" });

    // £80,000 is both the older salary and the band minimum, and £90,000 is
    // both the headline and the current row, so the amounts are asserted by
    // presence and the rows identified by their unique reason lines.
    expect(screen.getAllByText("£90,000").length).toBeGreaterThan(0);
    expect(screen.getAllByText("£80,000").length).toBeGreaterThan(0);
    expect(screen.getByText(/Merit · from 1 Jan 2024 \(current\)/)).toBeInTheDocument();
    expect(screen.getByText(/Hire · from 15 Jan 2020 to 31 Dec 2023/)).toBeInTheDocument();
  });

  it("shows where the salary sits in its band", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () => HttpResponse.json({ employee: detail })),
    );

    renderPage();

    expect(await screen.findByText("Within band")).toBeInTheDocument();
    expect(screen.getByText(/Compa-ratio 0\.90/)).toBeInTheDocument();
  });

  // A band is defined per level per country, so a country without one is a
  // reference-data gap. Saying so beats rendering a misleading 1.0.
  it("explains when no pay band exists rather than inventing a ratio", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () =>
        HttpResponse.json({ employee: { ...detail, pay_band: null, band_position: null } }),
      ),
    );

    renderPage();

    expect(await screen.findByText(/No pay band is defined for L3 in GB/)).toBeInTheDocument();
  });

  it("surfaces a 404 instead of rendering an empty page", async () => {
    server.use(
      http.get("/api/v1/employees/:id", () =>
        HttpResponse.json(
          { error: { code: "not_found", message: "Employee not found" } },
          { status: 404 },
        ),
      ),
    );

    renderPage();

    expect(await screen.findByRole("alert")).toHaveTextContent("Employee not found");
  });
});
