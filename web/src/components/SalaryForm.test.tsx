import { describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { renderWithProviders } from "../test/render";
import { server } from "../test/server";
import { SalaryForm } from "./SalaryForm";

function setup(props: Partial<Parameters<typeof SalaryForm>[0]> = {}) {
  const onRecorded = vi.fn();

  renderWithProviders(
    <SalaryForm
      employeeId={1}
      currency="USD"
      currentAmountCents={10_000_000}
      onRecorded={onRecorded}
      {...props}
    />,
  );

  return { onRecorded };
}

const amountField = () => screen.getByLabelText(/New salary \(USD\)/);
const submit = () => screen.getByRole("button", { name: "Record change" });

describe("SalaryForm", () => {
  it("shows the currency the employee is paid in", () => {
    setup({ currency: "PLN" });

    expect(screen.getByLabelText(/New salary \(PLN\)/)).toBeInTheDocument();
  });

  it("offers the change reasons the server published", async () => {
    const user = userEvent.setup();
    setup();

    await user.click(screen.getByRole("combobox", { name: /Reason/ }));

    expect(await screen.findByRole("option", { name: "Merit" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Promotion" })).toBeInTheDocument();
    // Corrections are a first-class reason, not a hidden path, because
    // history is append-only and cannot be edited.
    expect(screen.getByRole("option", { name: "Correction" })).toBeInTheDocument();
  });

  describe("amount parsing", () => {
    it("previews what will be recorded", async () => {
      const user = userEvent.setup();
      setup();

      await user.type(amountField(), "120000");

      expect(await screen.findByText(/Recording \$120,000/)).toBeInTheDocument();
    });

    it("shows the change against the current salary", async () => {
      const user = userEvent.setup();
      setup({ currentAmountCents: 10_000_000 });

      await user.type(amountField(), "110000");

      expect(await screen.findByText(/10\.0% increase/)).toBeInTheDocument();
    });

    it("recognises a decrease", async () => {
      const user = userEvent.setup();
      setup({ currentAmountCents: 10_000_000 });

      await user.type(amountField(), "90000");

      expect(await screen.findByText(/decrease/)).toBeInTheDocument();
    });

    // parseFloat("19.99") * 100 is 1998.9999999999998, which truncates to
    // 1998 — a cent lost on exactly the values people type most.
    it("parses cents exactly, without floating point drift", async () => {
      const user = userEvent.setup();
      let recorded: { amount_cents?: number } = {};

      server.use(
        http.post("/api/v1/employees/:id/salaries", async ({ request }) => {
          const body = (await request.json()) as { salary: { amount_cents: number } };
          recorded = body.salary;
          return HttpResponse.json({ salary: { id: 1 } }, { status: 201 });
        }),
      );

      setup();
      await user.type(amountField(), "19.99");
      await user.click(submit());

      await waitFor(() => expect(recorded.amount_cents).toBe(1999));
    });

    it("rejects an amount that is not a number", async () => {
      const user = userEvent.setup();
      const { onRecorded } = setup();

      await user.type(amountField(), "lots");
      await user.click(submit());

      expect(await screen.findByText(/Enter an amount/)).toBeInTheDocument();
      expect(onRecorded).not.toHaveBeenCalled();
    });

    it("rejects more than two decimal places", async () => {
      const user = userEvent.setup();
      const { onRecorded } = setup();

      await user.type(amountField(), "100.999");
      await user.click(submit());

      expect(await screen.findByText(/Enter an amount/)).toBeInTheDocument();
      expect(onRecorded).not.toHaveBeenCalled();
    });

    it("accepts a thousands separator, since people type them", async () => {
      const user = userEvent.setup();
      setup();

      await user.type(amountField(), "120,000");

      expect(await screen.findByText(/Recording \$120,000/)).toBeInTheDocument();
    });
  });

  describe("submitting", () => {
    it("sends the amount, currency, date and reason", async () => {
      const user = userEvent.setup();
      let body: unknown;

      server.use(
        http.post("/api/v1/employees/:id/salaries", async ({ request }) => {
          body = await request.json();
          return HttpResponse.json({ salary: { id: 1 } }, { status: 201 });
        }),
      );

      setup();
      await user.type(amountField(), "125000");
      await user.click(submit());

      await waitFor(() =>
        expect(body).toEqual({
          salary: {
            amount_cents: 12_500_000,
            currency: "USD",
            effective_from: expect.any(String),
            change_reason: "merit",
          },
        }),
      );
    });

    it("calls back and clears the field on success", async () => {
      const user = userEvent.setup();
      const { onRecorded } = setup();

      await user.type(amountField(), "125000");
      await user.click(submit());

      await waitFor(() => expect(onRecorded).toHaveBeenCalled());
      expect(amountField()).toHaveValue("");
    });

    // The server is the authority on this, not the date input's max
    // attribute, so the error it returns has to be shown.
    it("shows the server's message when a future date is refused", async () => {
      const user = userEvent.setup();

      server.use(
        http.post("/api/v1/employees/:id/salaries", () =>
          HttpResponse.json(
            {
              error: {
                code: "validation_failed",
                message: "Effective from cannot be in the future",
                details: { effective_from: ["cannot be in the future"] },
              },
            },
            { status: 422 },
          ),
        ),
      );

      setup();
      await user.type(amountField(), "125000");
      await user.click(submit());

      expect(await screen.findByRole("alert")).toHaveTextContent(
        "Effective from cannot be in the future",
      );
    });

    it("shows the server's message when the period overlaps", async () => {
      const user = userEvent.setup();

      server.use(
        http.post("/api/v1/employees/:id/salaries", () =>
          HttpResponse.json(
            {
              error: {
                code: "unprocessable",
                message: "salary period overlaps an existing one",
              },
            },
            { status: 422 },
          ),
        ),
      );

      setup();
      await user.type(amountField(), "125000");
      await user.click(submit());

      expect(await screen.findByRole("alert")).toHaveTextContent(/overlaps an existing one/);
    });

    it("keeps what was typed when the server rejects it", async () => {
      const user = userEvent.setup();

      server.use(
        http.post("/api/v1/employees/:id/salaries", () =>
          HttpResponse.json(
            { error: { code: "unprocessable", message: "Nope" } },
            { status: 422 },
          ),
        ),
      );

      setup();
      await user.type(amountField(), "125000");
      await user.click(submit());

      await screen.findByRole("alert");
      expect(amountField()).toHaveValue("125000");
    });
  });
});
