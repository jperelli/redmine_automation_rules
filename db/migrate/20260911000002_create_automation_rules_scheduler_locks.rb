active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreateAutomationRulesSchedulerLocks < active_record_migration_class
  def self.up
    create_table :automation_rules_scheduler_locks do |t|
      t.datetime :last_run_at, null: true
    end
  end

  def self.down
    drop_table :automation_rules_scheduler_locks
  end
end
