active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreateAutomationRulesRuns < active_record_migration_class
  def self.up
    create_table :automation_rules_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :last_run_at, null: false
      t.integer :duration_ms, null: false, default: 0
      t.string :source, limit: 20, null: false
      t.integer :rules_evaluated, null: false, default: 0
      t.integer :issues_matched, null: false, default: 0
      t.integer :actions_applied, null: false, default: 0
      t.integer :runs_count, null: false, default: 1
      t.text :error_messages
      t.text :notes
    end
    add_index :automation_rules_runs, :started_at
  end

  def self.down
    drop_table :automation_rules_runs
  end
end
