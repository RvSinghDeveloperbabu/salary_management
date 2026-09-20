# Append-only record of who changed what.
#
# Compensation data carries legal weight. "Who gave this person a raise, and
# when did they record it?" is a question an HR manager will eventually be
# asked by someone with a subpoena, and the salaries table alone answers only
# half of it.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      # The user who performed the action. Foreign key added in phase 4
      # alongside the users table. Nullable because seeded history has no
      # human author.
      t.bigint :actor_id

      t.string :subject_type, null: false
      t.bigint :subject_id, null: false

      t.string :action, null: false

      # Whatever is worth knowing about this specific change: amounts,
      # previous values, the reason given. Deliberately schemaless, because
      # constraining it would mean a migration every time a new action is
      # recorded.
      t.json :metadata

      # created_at only. An audit event that can be updated is not an audit
      # event, so there is nothing for updated_at to mean.
      t.datetime :created_at, null: false
    end

    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :actor_id
    add_index :audit_events, :created_at
  end
end
