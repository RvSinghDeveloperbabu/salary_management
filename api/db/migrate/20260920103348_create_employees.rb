class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      # The identifier the HR manager actually uses. Separate from the
      # primary key so it can be quoted in a conversation, and excluded from
      # strong parameters so it cannot be reassigned. See CLAUDE.md
      # testing rules on mass assignment.
      t.string :employee_code, null: false

      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false

      # ISO 3166-1 alpha-2. Denormalised onto the employee rather than read
      # through the department, because people in one department are spread
      # across countries and pay bands are per country.
      t.string :country_code, null: false, limit: 2

      t.references :department, null: false, foreign_key: true
      t.references :job_level, null: false, foreign_key: true

      # Self-referential. Nullable: someone has to be at the top, and a new
      # hire may not have a manager assigned yet.
      t.references :manager, null: true, foreign_key: { to_table: :employees }

      t.string :employment_type, null: false
      t.string :status, null: false, default: "active"

      t.date :hired_on, null: false
      t.date :terminated_on

      t.timestamps
    end

    add_index :employees, :employee_code, unique: true
    add_index :employees, :email, unique: true
    add_index :employees, :country_code
    add_index :employees, :status

    # The dominant filter in the directory and in every analytics query:
    # active employees, optionally narrowed to one department. Named in
    # docs/architecture.md.
    add_index :employees, [ :status, :department_id ]

    # Sorting the directory by name is the default, and it pages.
    add_index :employees, [ :last_name, :first_name ]

    add_check_constraint :employees,
      "status IN ('active', 'terminated')",
      name: "employees_known_status"

    add_check_constraint :employees,
      "employment_type IN ('full_time', 'part_time', 'contract')",
      name: "employees_known_employment_type"

    # A termination cannot precede the hire it ends.
    add_check_constraint :employees,
      "terminated_on IS NULL OR terminated_on >= hired_on",
      name: "employees_termination_after_hire"

    # Status and terminated_on must agree. Without this the headcount and
    # the leaver report can disagree with each other, and both look right.
    add_check_constraint :employees,
      "(status = 'terminated' AND terminated_on IS NOT NULL) OR " \
      "(status = 'active' AND terminated_on IS NULL)",
      name: "employees_status_matches_termination_date"
  end
end
