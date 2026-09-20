# An immutable record of a change. Written by services, never by controllers.
class AuditEvent < ApplicationRecord
  ACTIONS = %w[
    salary_recorded
    employee_created
    employee_updated
  ].freeze

  belongs_to :subject, polymorphic: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :subject_type, :subject_id, presence: true

  before_update :reject_mutation
  before_destroy :reject_mutation

  scope :most_recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_subject, ->(record) {
    where(subject_type: record.class.name, subject_id: record.id)
  }

  private

  # An audit trail that can be edited proves nothing.
  def reject_mutation
    raise ActiveRecord::ReadOnlyRecord, "audit events are immutable"
  end
end
