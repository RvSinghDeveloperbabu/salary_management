# Denormalised pointer to the salary row in effect today.
#
# Without it, "current pay for everyone" is a correlated subquery per
# employee. With it, it is a single join. docs/decisions.md 1 accepts the
# duplication precisely to buy that, and Salaries::RecordChange is the only
# thing allowed to maintain it.
class AddCurrentSalaryToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_reference :employees, :current_salary,
      null: true,
      foreign_key: { to_table: :salaries }
  end
end
