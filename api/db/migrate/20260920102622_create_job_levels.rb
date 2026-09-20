class CreateJobLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :job_levels do |t|
      t.string :name, null: false
      # Sort order. Name is "L1".."L6" today, but sorting on a label breaks
      # the moment a level is called "Principal", so ordering gets its own
      # column. docs/architecture.md sorts the directory on job_levels.rank.
      t.integer :rank, null: false

      t.timestamps
    end

    add_index :job_levels, :name, unique: true
    add_index :job_levels, :rank, unique: true
  end
end
