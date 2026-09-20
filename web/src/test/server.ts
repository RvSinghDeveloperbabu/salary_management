// MSW intercepts fetch during tests and answers with fixed JSON.
//
// The component under test still calls fetch exactly as it does in the
// browser — nothing is stubbed inside the app. That means these tests
// exercise the real client code, including error handling, rather than a
// mock of it.

import { setupServer } from "msw/node";
import { http, HttpResponse } from "msw";
import type { Employee, EmployeeList, Reference } from "../api/types";

export const reference: Reference = {
  departments: [
    { id: 1, name: "Engineering", cost_centre: "CC-1000" },
    { id: 2, name: "Sales", cost_centre: "CC-3000" },
  ],
  job_levels: [
    { id: 10, name: "L1", rank: 1 },
    { id: 11, name: "L3", rank: 3 },
  ],
  countries: ["GB", "US"],
  currencies: ["GBP", "USD"],
  statuses: ["active", "terminated"],
  employment_types: ["full_time", "part_time", "contract"],
  change_reasons: ["hire", "merit", "promotion", "market_adjustment", "correction"],
  sortable: ["name", "hired_on", "salary", "department", "level"],
};

export function buildEmployee(overrides: Partial<Employee> = {}): Employee {
  return {
    id: 1,
    employee_code: "EMP-00001",
    first_name: "Ada",
    last_name: "Lovelace",
    full_name: "Ada Lovelace",
    email: "ada@example.com",
    country_code: "GB",
    employment_type: "full_time",
    status: "active",
    hired_on: "2022-03-01",
    terminated_on: null,
    department: reference.departments[0],
    job_level: reference.job_levels[1],
    current_salary: {
      id: 100,
      amount_cents: 9_000_000,
      currency: "GBP",
      amount_base_cents: 11_430_000,
      effective_from: "2025-01-01",
      change_reason: "merit",
    },
    ...overrides,
  };
}

export function buildEmployeeList(employees: Employee[]): EmployeeList {
  return {
    employees,
    pagination: {
      page: 1,
      per_page: 25,
      total_count: employees.length,
      total_pages: 1,
    },
  };
}

/** Handlers every test starts with. Individual tests override as needed. */
export const handlers = [
  http.get("/api/v1/reference", () => HttpResponse.json(reference)),

  http.get("/api/v1/employees", () =>
    HttpResponse.json(buildEmployeeList([buildEmployee()])),
  ),

  http.post("/api/v1/employees/:id/salaries", () =>
    HttpResponse.json({ salary: { id: 200 }, previous_salary_id: 100 }, { status: 201 }),
  ),
];

export const server = setupServer(...handlers);
