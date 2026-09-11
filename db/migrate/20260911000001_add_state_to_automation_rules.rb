active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

# Per-rule runtime state kept by actions, e.g. the round-robin assignee position.
class AddStateToAutomationRules < active_record_migration_class
  def self.up
    add_column :automation_rules, :state, :text
  end

  def self.down
    remove_column :automation_rules, :state
  end
end
