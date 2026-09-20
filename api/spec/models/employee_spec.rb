require "rails_helper"

RSpec.describe Employee do
  subject { build(:employee) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:department) }
    it { is_expected.to belong_to(:job_level) }
    it { is_expected.to belong_to(:manager).class_name("Employee").optional }
    it { is_expected.to have_many(:reports).class_name("Employee").dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_presence_of(:hired_on) }
    it { is_expected.to validate_length_of(:country_code).is_equal_to(2) }
    it { is_expected.to validate_uniqueness_of(:employee_code).ignoring_case_sensitivity }
    it { is_expected.to validate_uniqueness_of(:email).ignoring_case_sensitivity }

    it "rejects a malformed email address" do
      expect(build(:employee, email: "not-an-address")).not_to be_valid
    end
  end

  # Assigned by the system, not the client: it is the identifier other
  # systems quote, so a request must not be able to choose or change it.
  describe "employee_code assignment" do
    it "assigns a code on create when none is given" do
      employee = described_class.create!(
        first_name: "Ada", last_name: "Lovelace", email: "ada@example.com",
        country_code: "US", department: create(:department), job_level: create(:job_level),
        employment_type: "full_time", status: "active", hired_on: 1.year.ago.to_date
      )

      expect(employee.employee_code).to match(/\AEMP-\d{5}\z/)
    end

    it "increments past the highest existing code" do
      create(:employee, employee_code: "EMP-00041")

      expect(create(:employee, employee_code: nil).employee_code).to eq("EMP-00042")
    end

    it "keeps an explicitly supplied code, so seeds stay reproducible" do
      expect(create(:employee, employee_code: "EMP-99999").employee_code).to eq("EMP-99999")
    end

    it "is still refused by the database if somehow left blank" do
      employee = build(:employee, employee_code: nil)
      employee.define_singleton_method(:assign_employee_code) { nil }

      expect { employee.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe "normalisation" do
    it "downcases the email and upcases the codes" do
      employee = create(:employee,
        email: "  Ada.Lovelace@Example.COM ",
        country_code: "pl",
        employee_code: "emp-00001")

      expect(employee.email).to eq("ada.lovelace@example.com")
      expect(employee.country_code).to eq("PL")
      expect(employee.employee_code).to eq("EMP-00001")
    end
  end

  describe "enums" do
    it "rejects an unknown employment type" do
      expect(build(:employee, employment_type: "freelance")).not_to be_valid
    end

    it "rejects an unknown status" do
      expect(build(:employee, status: "on_leave")).not_to be_valid
    end
  end

  # Headcount reads status. The leaver report reads terminated_on. If the two
  # are allowed to disagree, both reports look correct while one is wrong.
  describe "status and termination date coherence" do
    it "requires a termination date when terminated" do
      employee = build(:employee, status: "terminated", terminated_on: nil)

      expect(employee).not_to be_valid
      expect(employee.errors[:terminated_on]).to be_present
    end

    it "forbids a termination date while active" do
      employee = build(:employee, status: "active", terminated_on: Date.current)

      expect(employee).not_to be_valid
      expect(employee.errors[:terminated_on]).to be_present
    end

    it "accepts a terminated employee with a date" do
      expect(build(:employee, :terminated)).to be_valid
    end

    it "rejects a termination date before the hire date" do
      employee = build(:employee, :terminated,
        hired_on: 1.year.ago.to_date,
        terminated_on: 2.years.ago.to_date)

      expect(employee).not_to be_valid
      expect(employee.errors[:terminated_on]).to be_present
    end

    it "is refused by the database when validations are skipped" do
      employee = build(:employee, status: "terminated", terminated_on: nil)

      expect { employee.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /employees_status_matches_termination_date/)
    end
  end

  describe "manager" do
    it "allows a manager" do
      manager = create(:employee)

      expect(build(:employee, manager: manager)).to be_valid
    end

    it "refuses to let an employee manage themselves" do
      employee = create(:employee)
      employee.manager_id = employee.id

      expect(employee).not_to be_valid
      expect(employee.errors[:manager_id]).to be_present
    end

    it "nullifies the manager link on reports when a manager is deleted" do
      manager = create(:employee)
      report = create(:employee, manager: manager)

      manager.destroy!

      expect(report.reload.manager_id).to be_nil
    end
  end

  describe "scopes" do
    let!(:active_us) { create(:employee) }
    let!(:leaver) { create(:employee, :terminated) }
    let!(:active_pl) { create(:employee, :in_poland) }

    it "active returns only active employees" do
      expect(described_class.active).to contain_exactly(active_us, active_pl)
    end

    it "terminated returns only leavers" do
      expect(described_class.terminated).to contain_exactly(leaver)
    end

    it "in_country matches case insensitively" do
      expect(described_class.in_country("pl")).to contain_exactly(active_pl)
    end

    it "in_department narrows to one department" do
      expect(described_class.in_department(active_us.department_id))
        .to contain_exactly(active_us)
    end

    it "at_level narrows to one level" do
      expect(described_class.at_level(active_us.job_level_id))
        .to contain_exactly(active_us)
    end
  end

  describe "#full_name" do
    it "joins the first and last name" do
      expect(build(:employee, first_name: "Ada", last_name: "Lovelace").full_name)
        .to eq("Ada Lovelace")
    end
  end

  describe "#pay_band" do
    it "returns the band for the employee's level in their own country" do
      employee = create(:employee, country_code: "PL")
      create(:pay_band, job_level: employee.job_level, country_code: "US")
      polish_band = create(:pay_band, :poland, job_level: employee.job_level)

      expect(employee.pay_band).to eq(polish_band)
    end

    it "is nil where no band exists for that level and country" do
      expect(create(:employee).pay_band).to be_nil
    end
  end
end
