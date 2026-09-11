active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreateAutomationRules < active_record_migration_class
  def self.up
    create_table :automation_rules do |t|
      t.integer :project_id
      t.integer :author_id, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.boolean :apply_to_subprojects, null: false, default: false
      t.boolean :note_marker, null: false, default: true
      t.integer :position
      t.string :trigger_type, limit: 30, null: false
      t.text :trigger_options
      t.text :conditions
      t.text :actions
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.text :last_error
      t.integer :runs_count, null: false, default: 0
      t.datetime :created_on, null: false
      t.datetime :updated_on, null: false
    end
    add_index :automation_rules, :project_id
    add_index :automation_rules, %i[trigger_type active]
  end

  def self.down
    drop_table :automation_rules
  end
end
