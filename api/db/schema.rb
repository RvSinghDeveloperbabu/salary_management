# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_20_111302) do
  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.json "metadata"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["created_at"], name: "index_audit_events_on_created_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject_type_and_subject_id"
  end

  create_table "departments", force: :cascade do |t|
    t.string "cost_centre", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["cost_centre"], name: "index_departments_on_cost_centre", unique: true
    t.index ["name"], name: "index_departments_on_name", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.integer "current_salary_id"
    t.integer "department_id", null: false
    t.string "email", null: false
    t.string "employee_code", null: false
    t.string "employment_type", null: false
    t.string "first_name", null: false
    t.date "hired_on", null: false
    t.integer "job_level_id", null: false
    t.string "last_name", null: false
    t.integer "manager_id"
    t.string "status", default: "active", null: false
    t.date "terminated_on"
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_employees_on_country_code"
    t.index ["current_salary_id"], name: "index_employees_on_current_salary_id"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["email"], name: "index_employees_on_email", unique: true
    t.index ["employee_code"], name: "index_employees_on_employee_code", unique: true
    t.index ["job_level_id"], name: "index_employees_on_job_level_id"
    t.index ["last_name", "first_name"], name: "index_employees_on_last_name_and_first_name"
    t.index ["manager_id"], name: "index_employees_on_manager_id"
    t.index ["status", "department_id"], name: "index_employees_on_status_and_department_id"
    t.index ["status"], name: "index_employees_on_status"
    t.check_constraint "(status = 'terminated' AND terminated_on IS NOT NULL) OR (status = 'active' AND terminated_on IS NULL)", name: "employees_status_matches_termination_date"
    t.check_constraint "employment_type IN ('full_time', 'part_time', 'contract')", name: "employees_known_employment_type"
    t.check_constraint "status IN ('active', 'terminated')", name: "employees_known_status"
    t.check_constraint "terminated_on IS NULL OR terminated_on >= hired_on", name: "employees_termination_after_hire"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.string "base_currency", limit: 3, null: false
    t.datetime "created_at", null: false
    t.string "quote_currency", limit: 3, null: false
    t.date "rate_on", null: false
    t.bigint "rate_ppm", null: false
    t.datetime "updated_at", null: false
    t.index ["base_currency", "quote_currency", "rate_on"], name: "index_exchange_rates_on_pair_and_date", unique: true
    t.check_constraint "rate_ppm > 0", name: "exchange_rates_positive_rate"
  end

  create_table "job_levels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "rank", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_job_levels_on_name", unique: true
    t.index ["rank"], name: "index_job_levels_on_rank", unique: true
  end

  create_table "pay_bands", force: :cascade do |t|
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.integer "job_level_id", null: false
    t.bigint "max_cents", null: false
    t.bigint "mid_cents", null: false
    t.bigint "min_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["job_level_id", "country_code"], name: "index_pay_bands_on_job_level_id_and_country_code", unique: true
    t.index ["job_level_id"], name: "index_pay_bands_on_job_level_id"
    t.check_constraint "min_cents <= mid_cents AND mid_cents <= max_cents", name: "pay_bands_ordered_bounds"
    t.check_constraint "min_cents > 0", name: "pay_bands_positive_minimum"
  end

  create_table "salaries", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "change_reason", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.integer "employee_id", null: false
    t.bigint "recorded_by_id"
    t.datetime "updated_at", null: false
    t.index ["employee_id", "effective_from"], name: "index_salaries_on_employee_id_and_effective_from", unique: true
    t.index ["employee_id"], name: "index_salaries_on_employee_id"
    t.index ["recorded_by_id"], name: "index_salaries_on_recorded_by_id"
    t.index ["updated_at"], name: "index_salaries_on_updated_at"
    t.check_constraint "amount_cents > 0", name: "salaries_positive_amount"
    t.check_constraint "change_reason IN ('hire', 'merit', 'promotion', 'market_adjustment', 'correction')", name: "salaries_known_change_reason"
    t.check_constraint "effective_to IS NULL OR effective_to >= effective_from", name: "salaries_period_ordered"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "audit_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "employees", "departments"
  add_foreign_key "employees", "employees", column: "manager_id"
  add_foreign_key "employees", "job_levels"
  add_foreign_key "employees", "salaries", column: "current_salary_id"
  add_foreign_key "pay_bands", "job_levels"
  add_foreign_key "salaries", "employees"
  add_foreign_key "salaries", "users", column: "recorded_by_id", on_delete: :nullify
  add_foreign_key "sessions", "users"
end
