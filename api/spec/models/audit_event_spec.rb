require "rails_helper"

RSpec.describe AuditEvent do
  subject { build(:audit_event) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to belong_to(:subject) }

    it "rejects an unknown action" do
      expect(build(:audit_event, action: "vibes_adjusted")).not_to be_valid
    end

    it "accepts every documented action" do
      described_class::ACTIONS.each do |action|
        expect(build(:audit_event, action: action)).to be_valid, "expected #{action} to be valid"
      end
    end
  end

  describe "immutability" do
    let!(:event) { create(:audit_event) }

    it "refuses to be updated" do
      event.action = "employee_updated"

      expect { event.save! }.to raise_error(ActiveRecord::ReadOnlyRecord, /immutable/)
    end

    it "refuses to be destroyed" do
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "metadata" do
    it "round-trips a hash through the json column" do
      event = create(:audit_event, metadata: { "amount_cents" => 123, "currency" => "USD" })

      expect(event.reload.metadata).to eq("amount_cents" => 123, "currency" => "USD")
    end
  end

  describe ".for_subject" do
    it "finds events recorded against a record" do
      employee = create(:employee)
      event = create(:audit_event, subject: employee)
      create(:audit_event, subject: create(:employee))

      expect(described_class.for_subject(employee)).to contain_exactly(event)
    end
  end
end
