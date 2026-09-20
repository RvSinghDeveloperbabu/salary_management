// Shapes returned by the Rails API.
//
// Every money value is an integer number of cents, paired with a currency
// code. The API never sends a decimal for money, so the frontend never
// parses one — see formatMoney in ../lib/money.ts for display.

export interface User {
  id: number;
  email_address: string;
}

export interface Department {
  id: number;
  name: string;
  cost_centre: string;
}

export interface JobLevel {
  id: number;
  name: string;
  rank: number;
}

export interface PayBand {
  id: number;
  country_code: string;
  currency: string;
  min_cents: number;
  mid_cents: number;
  max_cents: number;
}

export type ChangeReason =
  | "hire"
  | "merit"
  | "promotion"
  | "market_adjustment"
  | "correction";

export interface Salary {
  id: number;
  amount_cents: number;
  currency: string;
  /** Same amount in USD, or null when no rate exists for the currency. */
  amount_base_cents: number | null;
  effective_from: string;
  effective_to: string | null;
  change_reason: ChangeReason;
  current: boolean;
}

/** The salary summary embedded in an employee row. */
export interface CurrentSalary {
  id: number;
  amount_cents: number;
  currency: string;
  amount_base_cents: number | null;
  effective_from: string;
  change_reason: ChangeReason;
}

export type EmploymentType = "full_time" | "part_time" | "contract";
export type EmployeeStatus = "active" | "terminated";

export interface Employee {
  id: number;
  employee_code: string;
  first_name: string;
  last_name: string;
  full_name: string;
  email: string;
  country_code: string;
  employment_type: EmploymentType;
  status: EmployeeStatus;
  hired_on: string;
  terminated_on: string | null;
  department: Department;
  job_level: JobLevel;
  current_salary: CurrentSalary | null;
}

export interface BandPosition {
  position: "below" | "within" | "above";
  compa_ratio: number;
}

export interface EmployeeDetail extends Omit<Employee, "current_salary"> {
  pay_band: PayBand | null;
  manager: { id: number; full_name: string; employee_code: string } | null;
  salaries: Salary[];
  current_salary: CurrentSalary | null;
  band_position: BandPosition | null;
  months_since_last_change: number | null;
}

export interface Pagination {
  page: number;
  per_page: number;
  total_count: number;
  total_pages: number;
}

export interface EmployeeList {
  employees: Employee[];
  pagination: Pagination;
}

/**
 * Summary statistics. Every field is null for an empty population, which is
 * deliberately different from zero: "no data for Brazil" and "everyone in
 * Brazil earns nothing" must not look the same.
 */
export interface Distribution {
  count: number;
  sum: number;
  mean: number | null;
  min: number | null;
  p25: number | null;
  p50: number | null;
  p75: number | null;
  max: number | null;
  interquartile_range: number | null;
}

export interface Split {
  group: string;
  headcount: number;
  total_annual_cents: number;
  median_cents: number | null;
}

export interface Overview {
  currency: string;
  as_of: string;
  headcount: number;
  total_annual_cents: number;
  salary: Distribution;
  splits: {
    department: Split[];
    country: Split[];
    job_level: Split[];
  };
}

export type GroupBy = "department" | "country" | "job_level";

export interface DistributionGroup extends Distribution {
  group: string;
}

export interface DistributionResponse {
  currency: string;
  as_of: string;
  group_by: GroupBy;
  groups: DistributionGroup[];
}

export interface TrendPoint {
  month: string;
  as_of: string;
  total_cents: number;
  headcount: number;
}

export interface PayrollTrend {
  currency: string;
  as_of: string;
  points: TrendPoint[];
}

export interface OutlierFinding {
  employee_id: number;
  employee_code: string;
  full_name: string;
  department: string;
  job_level: string;
  country_code: string;
  amount_cents: number;
  currency: string;
  amount_base_cents: number | null;
  effective_from: string;
  months_since_change: number;
  band_min_cents: number | null;
  band_mid_cents: number | null;
  band_max_cents: number | null;
  compa_ratio: number | null;
  shortfall_cents: number | null;
}

export interface OutliersResponse {
  currency_note: string;
  stale_after_months: number;
  below_band: OutlierFinding[];
  above_band: OutlierFinding[];
  stale: OutlierFinding[];
  counts: { below_band: number; above_band: number; stale: number };
}

export interface Reference {
  departments: Department[];
  job_levels: JobLevel[];
  countries: string[];
  currencies: string[];
  statuses: EmployeeStatus[];
  employment_types: EmploymentType[];
  change_reasons: ChangeReason[];
  sortable: string[];
}

/** The error envelope every failing endpoint returns. */
export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    details?: Record<string, string[]>;
  };
}
