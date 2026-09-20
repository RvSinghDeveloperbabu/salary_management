require "rails_helper"

RSpec.describe User do
  subject { build(:user) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to have_many(:sessions).dependent(:destroy) }
    it { is_expected.to validate_presence_of(:email_address) }
    it { is_expected.to validate_uniqueness_of(:email_address).ignoring_case_sensitivity }

    it "rejects a malformed email address" do
      expect(build(:user, email_address: "not-an-address")).not_to be_valid
    end

    # An account that can read every salary in the organisation should not
    # be protected by a four-character password.
    it "rejects a short password" do
      user = build(:user, password: "short", password_confirmation: "short")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts a password of twelve characters" do
      expect(build(:user, password: "a" * 12, password_confirmation: "a" * 12)).to be_valid
    end
  end

  describe "normalisation" do
    it "downcases and strips the email address" do
      user = create(:user, email_address: "  HR@Example.COM  ")

      expect(user.email_address).to eq("hr@example.com")
    end
  end

  describe "password storage" do
    it "stores a digest, never the password" do
      user = create(:user, password: "compensation2026", password_confirmation: "compensation2026")

      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to include("compensation2026")
    end
  end

  describe ".authenticate_by" do
    let!(:user) do
      create(:user, email_address: "hr@example.com", password: "compensation2026",
        password_confirmation: "compensation2026")
    end

    it "returns the user for correct credentials" do
      expect(described_class.authenticate_by(
        email_address: "hr@example.com", password: "compensation2026"
      )).to eq(user)
    end

    it "returns nil for a wrong password" do
      expect(described_class.authenticate_by(
        email_address: "hr@example.com", password: "wrong"
      )).to be_nil
    end

    it "returns nil for an unknown address" do
      expect(described_class.authenticate_by(
        email_address: "nobody@example.com", password: "compensation2026"
      )).to be_nil
    end
  end
end
