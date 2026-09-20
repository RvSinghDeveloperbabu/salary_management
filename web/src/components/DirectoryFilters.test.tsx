import { describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders } from "../test/render";
import { reference } from "../test/server";
import { DirectoryFilters, EMPTY_FILTERS, type FilterState } from "./DirectoryFilters";

function setup(overrides: Partial<FilterState> = {}) {
  const onChange = vi.fn();
  const value = { ...EMPTY_FILTERS, ...overrides };

  renderWithProviders(
    <DirectoryFilters value={value} onChange={onChange} reference={reference} />,
  );

  return { onChange, value };
}

describe("DirectoryFilters", () => {
  it("renders every filter control", () => {
    setup();

    expect(screen.getByLabelText("Search employees")).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Department" })).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Level" })).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Country" })).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Status" })).toBeInTheDocument();
  });

  it("reports what was typed in the search box", async () => {
    const user = userEvent.setup();
    const { onChange } = setup();

    await user.type(screen.getByLabelText("Search employees"), "A");

    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ q: "A" }));
  });

  // Options come from /reference rather than being hard-coded, so the UI
  // cannot drift out of step with the database.
  it("offers the departments the server returned", async () => {
    const user = userEvent.setup();
    setup();

    await user.click(screen.getByRole("combobox", { name: "Department" }));

    expect(await screen.findByRole("option", { name: "Engineering" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Sales" })).toBeInTheDocument();
  });

  it("offers only the countries employees are actually in", async () => {
    const user = userEvent.setup();
    setup();

    await user.click(screen.getByRole("combobox", { name: "Country" }));

    expect(await screen.findByRole("option", { name: "GB" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "US" })).toBeInTheDocument();
    expect(screen.queryByRole("option", { name: "FR" })).not.toBeInTheDocument();
  });

  it("reports the id, not the label, when a department is chosen", async () => {
    const user = userEvent.setup();
    const { onChange } = setup();

    await user.click(screen.getByRole("combobox", { name: "Department" }));
    await user.click(await screen.findByRole("option", { name: "Engineering" }));

    await waitFor(() =>
      expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ department_id: "1" })),
    );
  });

  // Active is the default because a directory listing leavers alongside
  // current staff answers a different question from the one being asked.
  it("defaults to showing active employees only", () => {
    setup();

    expect(screen.getByRole("combobox", { name: "Status" })).toHaveValue("Active");
  });

  it("hides the reset button until something is filtered", () => {
    setup();

    expect(screen.queryByRole("button", { name: "Reset" })).not.toBeInTheDocument();
  });

  it("shows the reset button once a filter is applied", () => {
    setup({ department_id: "1" });

    expect(screen.getByRole("button", { name: "Reset" })).toBeInTheDocument();
  });

  it("clears every filter back to the default when reset", async () => {
    const user = userEvent.setup();
    const { onChange } = setup({ q: "ada", department_id: "1", country_code: "GB" });

    await user.click(screen.getByRole("button", { name: "Reset" }));

    expect(onChange).toHaveBeenCalledWith(EMPTY_FILTERS);
  });

  // A blank value means "no filter". Sending null or undefined would put
  // `department_id=` in the query string, which is a filter matching
  // nothing rather than no filter at all.
  //
  // Queried through the DOM because Mantine's clear button carries no
  // accessible name, so getByRole cannot reach it. That is worth a note:
  // a control a screen reader cannot announce is also one a role-based
  // test cannot find, and the two limitations have the same root cause.
  it("reports an empty string when a filter is cleared", async () => {
    const user = userEvent.setup();
    const { onChange } = setup({ department_id: "1" });

    const clearButton = document.querySelector<HTMLButtonElement>(
      '[data-combined-clear-section="true"] button',
    );
    expect(clearButton).not.toBeNull();

    await user.click(clearButton!);

    await waitFor(() => {
      const calls = onChange.mock.calls.map(([next]) => next as FilterState);
      expect(calls.some((call) => call.department_id === "")).toBe(true);
    });
  });
});
