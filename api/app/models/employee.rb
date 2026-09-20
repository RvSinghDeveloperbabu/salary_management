class Employee < ApplicationRecord
  EMPLOYMENT_TYPES = %w[full_time part_time contract].freeze
  STATUSES = %w[active terminated].freeze

  belongs_to :department
  belongs_to :job_level
  belongs_to :manager, class_name: "Employee", optional: true

  has_many :reports, class_name: "Employee", foreign_key: :manager_id, dependent: :nullify,
    inverse_of: :manager

  has_many :salaries, dependent: :destroy

  # Denormalised pointer, maintained only by Salaries::RecordChange. Turns
  # "current pay for everyone" from a correlated subquery per row into a
  # single join. See docs/decisions.md 1.
  belongs_to :current_salary, class_name: "Salary", optional: true

  enum :employment_type, EMPLOYMENT_TYPES.index_by(&:itself), validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  normalizes :email, with: ->(value) { value.strip.downcase }
  normalizes :country_code, with: ->(value) { value.strip.upcase }
  normalizes :employee_code, with: ->(value) { value.strip.upcase }

  validates :employee_code, presence: true, uniqueness: { case_sensitive: false }
  validates :first_name, :last_name, presence: true
  validates :email,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :country_code, presence: true, length: { is: 2 }
  validates :hired_on, presence: true

  validate :termination_must_follow_hire
  validate :termination_date_must_match_status
  validate :manager_must_not_be_self

  scope :active, -> { where(status: "active") }
  scope :terminated, -> { where(status: "terminated") }
  scope :in_department, ->(id) { where(department_id: id) }
  scope :in_country, ->(code) { where(country_code: code.to_s.upcase) }
  scope :at_level, ->(id) { where(job_level_id: id) }

  # Loads everything the directory row and the detail header need. Used by
  # Queries::EmployeeSearch so a 50-row page stays at a handful of queries
  # rather than one per row (CLAUDE.md non-negotiable 5).
  scope :with_directory_associations, -> { includes(:department, :job_level, :current_salary) }

  def full_name
    "#{first_name} #{last_name}"
  end

  # The band governing this employee: their level, in their country. Nil
  # where no band has been defined for that combination.
  def pay_band
    job_level&.band_for(country_code)
  end

  private

  def termination_must_follow_hire
    return if terminated_on.blank? || hired_on.blank?

    errors.add(:terminated_on, "cannot be before the hire date") if terminated_on < hired_on
  end

  # Mirrors the employees_status_matches_termination_date check constraint.
  # Headcount reads status; the leaver report reads terminated_on. If the two
  # can disagree, both reports look correct while one of them is wrong.
  def termination_date_must_match_status
    if status == "terminated" && terminated_on.blank?
      errors.add(:terminated_on, "is required when the employee is terminated")
    elsif status == "active" && terminated_on.present?
      errors.add(:terminated_on, "must be blank while the employee is active")
    end
  end

  def manager_must_not_be_self
    return if manager_id.blank? || id.blank?

    errors.add(:manager_id, "cannot be the employee themselves") if manager_id == id
  end
end
