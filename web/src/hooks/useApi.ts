// Every data-loading hook in the app, in one file.
//
// Each is a thin wrapper over useQuery. Read `queryKey` as "the cache entry
// this data lives under" — when anything in the key changes, TanStack Query
// refetches; when it changes back, the cached answer is served instantly.
//
// `queryFn` is just a function returning a promise. Ours call apiGet, which
// calls fetch. Nothing is hidden.

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost } from "../api/client";
import type {
  DistributionResponse,
  EmployeeDetail,
  EmployeeList,
  GroupBy,
  Overview,
  OutliersResponse,
  PayrollTrend,
  Reference,
} from "../api/types";

export interface DirectoryFilters {
  q?: string;
  department_id?: string;
  job_level_id?: string;
  country_code?: string;
  status?: string;
  employment_type?: string;
  sort?: string;
  direction?: string;
  page?: number;
  per_page?: number;
}

export interface AnalyticsFilters {
  department_id?: string;
  job_level_id?: string;
  country_code?: string;
}

/**
 * Departments, levels, countries and the permitted sort keys, in one
 * request. Reference data changes about never, so it is cached for the
 * session rather than refetched per screen.
 */
export function useReference() {
  return useQuery({
    queryKey: ["reference"],
    queryFn: () => apiGet<Reference>("/reference"),
    staleTime: Infinity,
  });
}

export function useEmployees(filters: DirectoryFilters) {
  return useQuery({
    queryKey: ["employees", filters],
    queryFn: () => apiGet<EmployeeList>("/employees", { ...filters }),
    // Keeps the previous page visible while the next one loads, so the
    // table does not collapse to a spinner on every page change.
    placeholderData: (previous) => previous,
  });
}

export function useEmployee(id: string | undefined) {
  return useQuery({
    queryKey: ["employee", id],
    queryFn: () => apiGet<EmployeeDetail>(`/employees/${id}`),
    // Without an id there is nothing to ask for.
    enabled: Boolean(id),
  });
}

export function useOverview(filters: AnalyticsFilters = {}) {
  return useQuery({
    queryKey: ["analytics", "overview", filters],
    queryFn: () => apiGet<Overview>("/analytics/overview", { ...filters }),
  });
}

export function useDistribution(groupBy: GroupBy, filters: AnalyticsFilters = {}) {
  return useQuery({
    queryKey: ["analytics", "distribution", groupBy, filters],
    queryFn: () =>
      apiGet<DistributionResponse>("/analytics/distribution", { group_by: groupBy, ...filters }),
  });
}

export function usePayrollTrend(months = 24, filters: AnalyticsFilters = {}) {
  return useQuery({
    queryKey: ["analytics", "payroll_trend", months, filters],
    queryFn: () => apiGet<PayrollTrend>("/analytics/payroll_trend", { months, ...filters }),
  });
}

export function useOutliers(filters: AnalyticsFilters = {}) {
  return useQuery({
    queryKey: ["analytics", "outliers", filters],
    queryFn: () => apiGet<OutliersResponse>("/analytics/outliers", { ...filters }),
  });
}

export interface RecordSalaryInput {
  employeeId: number;
  amount_cents: number;
  currency: string;
  effective_from: string;
  change_reason: string;
}

/**
 * Recording a salary change.
 *
 * useMutation is useQuery's counterpart for writes. The important part is
 * the onSuccess: recording a raise changes this employee, the directory
 * listing and every analytics figure, so those cache entries are marked
 * stale and refetched. Without it the dashboard would keep showing the old
 * payroll total until a manual reload.
 */
export function useRecordSalary() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ employeeId, ...salary }: RecordSalaryInput) =>
      apiPost(`/employees/${employeeId}/salaries`, { salary }),

    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["employee", String(variables.employeeId)] });
      queryClient.invalidateQueries({ queryKey: ["employees"] });
      queryClient.invalidateQueries({ queryKey: ["analytics"] });
    },
  });
}
