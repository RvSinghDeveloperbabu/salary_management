class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.string :name, null: false
      t.string :cost_centre, null: false

      t.timestamps
    end

    # Both are natural keys the HR manager will recognise, and the seed
    # relies on them being unique to stay idempotent.
    add_index :departments, :name, unique: true
    add_index :departments, :cost_centre, unique: true
  end
end
