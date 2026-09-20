module Salaries
  # The only write path into the salaries table.
  #
  # Recording a raise is three writes that must all happen or none of them:
  # close the period on the outgoing row, insert the new one, and repoint
  # employees.current_salary_id. A partial failure leaves the denormalised
  # pointer disagreeing with the history, and every analytics number is
  # derived from one or the other.
  #
  # Controllers call this. Nothing else inserts a salary.
  class RecordChange
    Result = Data.define(:salary, :previous) do
      def first_salary?
        previous.nil?
      end
    end

    class Error < StandardError; end

    # Raised when the caller tries to insert history behind an existing row.
    # Backdating is a correction to the record, which needs a different
    # conversation than "record this raise".
    class OutOfOrder < Error; end

    def initialize(employee:, amount_cents:, currency:, effective_from:, change_reason:,
                   recorded_by: nil)
      @employee = employee
      @amount_cents = amount_cents
      @currency = currency
      @effective_from = effective_from
      @change_reason = change_reason
      @recorded_by = recorded_by
    end

    # Returns a Result. Raises ActiveRecord::RecordInvalid if the new row
    # fails validation, so the caller can render 422 from the messages.
    def call
      employee.with_lock do
        previous = current_open_salary

        assert_in_order!(previous)

        # Close the outgoing period the day before the new one opens, so the
        # two never both cover the same day.
        previous&.update!(effective_to: effective_from - 1)

        salary = build_salary
        salary.save!

        # Denormalised pointer, maintained inside the same transaction as
        # the insert. docs/decisions.md 1 accepts the duplication to turn
        # "current pay for everyone" into a single join.
        employee.update_column(:current_salary_id, salary.id)

        record_audit_event(salary, previous)

        Result.new(salary: salary, previous: previous)
      end
    end

    private

    attr_reader :employee, :amount_cents, :currency, :effective_from, :change_reason,
                :recorded_by

    def current_open_salary
      employee.salaries.open_ended.order(effective_from: :desc).first
    end

    def assert_in_order!(previous)
      return if previous.nil?
      return if effective_from > previous.effective_from

      raise OutOfOrder,
        "effective_from #{effective_from} is not after the current salary, " \
        "which starts on #{previous.effective_from}. Backdating is a correction, " \
        "not a change."
    end

    def build_salary
      employee.salaries.build(
        amount_cents: amount_cents,
        currency: currency,
        effective_from: effective_from,
        change_reason: change_reason,
        recorded_by_id: recorded_by&.id
      )
    end

    # Inside the transaction: an audit trail missing the change it was meant
    # to record is worse than no audit trail, because it looks complete.
    def record_audit_event(salary, previous)
      AuditEvent.create!(
        actor_id: recorded_by&.id,
        subject: employee,
        action: "salary_recorded",
        metadata: {
          salary_id: salary.id,
          amount_cents: salary.amount_cents,
          currency: salary.currency,
          effective_from: salary.effective_from.to_s,
          change_reason: salary.change_reason,
          previous_salary_id: previous&.id,
          previous_amount_cents: previous&.amount_cents
        }
      )
    end
  end
end
