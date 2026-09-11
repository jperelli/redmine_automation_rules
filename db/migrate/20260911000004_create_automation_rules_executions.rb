active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreateAutomationRulesExecutions < active_record_migration_class
  def self.up
    create_table :automation_rules_executions do |t|
      t.integer :automation_rule_id, null: false
      t.integer :issue_id
      t.string :trigger, limit: 30, null: false
      t.text :applied
      t.text :error
      t.datetime :created_at, null: false
    end
    add_index :automation_rules_executions, %i[automation_rule_id id], name: 'index_ar_executions_on_rule_and_id'
    add_index :automation_rules_executions, :issue_id
  end

  def self.down
    drop_table :automation_rules_executions
  end
end
