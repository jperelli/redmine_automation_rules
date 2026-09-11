module RedmineAutomationRules
  # Built-in rules the "New rule from recipe" menu pre-fills the form with.
  # Each recipe is a method returning rule attributes. Statuses, priorities,
  # roles, groups and custom fields are looked up by their usual names and
  # fall back to what the Redmine instance has, so every recipe builds a
  # valid rule the user then adjusts in the form.
  module Recipes
    extend Redmine::I18n

    KEYS = %w[
      auto_close_resolved reopen_on_reporter_note close_parent_when_subtasks_closed
      round_robin_unassigned start_date_on_progress finish_on_close escalate_unassigned_high_priority
      due_date_reminder stale_issues assign_by_category time_budget_exceeded
    ].freeze

    class << self
      def keys
        KEYS
      end

      def options
        KEYS.map { |key| [l("automation_rules_recipe_#{key}"), key] }
      end

      def build(key, project: nil, user: nil)
        return nil unless KEYS.include?(key.to_s)

        Builder.new(project, user).public_send(key)
      end
    end

    class Builder
      include Redmine::I18n

      attr_reader :project, :user

      def initialize(project, user)
        @project = project
        @user = user
      end

      def auto_close_resolved
        rule('auto_close_resolved', 'scheduled',
             trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day', 'time_of_day' => '02:00' },
             conditions: [
               { 'type' => 'status', 'operator' => 'is', 'value' => id(status_named('Resolved', closed: false)) },
               { 'type' => 'updated_ago', 'operator' => 'more_than_days', 'value' => '14' }
             ],
             actions: [
               { 'type' => 'add_note', 'text' => l(:automation_rules_recipe_auto_close_resolved_note) },
               { 'type' => 'close_issue' }
             ])
      end

      def reopen_on_reporter_note
        rule('reopen_on_reporter_note', 'issue_updated',
             trigger_options: { 'change' => 'note' },
             conditions: [
               { 'type' => 'status', 'operator' => 'is_closed' },
               { 'type' => 'author', 'operator' => 'is_current_user' }
             ],
             actions: [{ 'type' => 'reopen_issue' }])
      end

      def close_parent_when_subtasks_closed
        rule('close_parent_when_subtasks_closed', 'issue_closed',
             conditions: [{ 'type' => 'parent', 'operator' => 'siblings_closed' }],
             actions: [{ 'type' => 'update_parent', 'action' => 'close_issue' }])
      end

      def round_robin_unassigned
        group = Group.givable.sorted.first
        action = if group
                   { 'type' => 'set_assignee', 'mode' => 'round_robin', 'group_id' => id(group) }
                 else
                   { 'type' => 'set_assignee', 'mode' => 'author' }
                 end
        rule('round_robin_unassigned', 'issue_created',
             conditions: [{ 'type' => 'assignee', 'operator' => 'is_nobody' }],
             actions: [action])
      end

      def start_date_on_progress
        in_progress = status_named('In Progress', closed: false)
        rule('start_date_on_progress', 'issue_updated',
             trigger_options: { 'change' => 'status_to', 'status_id' => id(in_progress) },
             actions: [{ 'type' => 'set_start_date', 'mode' => 'today', 'only_if_empty' => '1' }])
      end

      def finish_on_close
        rule('finish_on_close', 'issue_closed',
             actions: [
               { 'type' => 'set_done_ratio', 'value' => '100' },
               { 'type' => 'set_due_date', 'mode' => 'today', 'only_if_empty' => '1' }
             ])
      end

      def escalate_unassigned_high_priority
        rule('escalate_unassigned_high_priority', 'scheduled',
             trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
             conditions: [
               { 'type' => 'priority', 'operator' => 'is_at_least', 'value' => id(priority_named('High')) },
               { 'type' => 'assignee', 'operator' => 'is_nobody' },
               { 'type' => 'created_ago', 'operator' => 'more_than_hours', 'value' => '4' }
             ],
             actions: [
               { 'type' => 'add_watchers', 'who' => 'role', 'role_id' => id(role_named('Manager')) },
               { 'type' => 'add_note', 'text' => l(:automation_rules_recipe_escalate_unassigned_high_priority_note) }
             ])
      end

      def due_date_reminder
        rule('due_date_reminder', 'scheduled',
             trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day', 'time_of_day' => '09:00' },
             conditions: [
               { 'type' => 'assignee', 'operator' => 'is_anybody' },
               { 'type' => 'due_date', 'operator' => 'within_days', 'days' => '2' }
             ],
             actions: [
               { 'type' => 'send_email', 'who' => 'assignee',
                 'subject' => l(:automation_rules_recipe_due_date_reminder_subject),
                 'body' => l(:automation_rules_recipe_due_date_reminder_body) }
             ])
      end

      def stale_issues
        actions = [{ 'type' => 'add_note', 'text' => l(:automation_rules_recipe_stale_issues_note) }]
        stale = IssueCustomField.find_by(name: 'Stale', field_format: 'bool')
        actions << { 'type' => 'set_custom_field', 'custom_field_id' => id(stale), 'value' => '1' } if stale
        rule('stale_issues', 'scheduled',
             trigger_options: { 'interval_number' => '1', 'interval_unit' => 'week', 'time_of_day' => '03:00' },
             conditions: [{ 'type' => 'updated_ago', 'operator' => 'more_than_days', 'value' => '90' }],
             actions: actions)
      end

      def assign_by_category
        category = project&.issue_categories&.first
        conditions = if category
                       [{ 'type' => 'category', 'operator' => 'is', 'value' => id(category) }]
                     else
                       [{ 'type' => 'category', 'operator' => 'is_set' }]
                     end
        assignee = category&.assigned_to || user
        rule('assign_by_category', 'issue_created',
             conditions: conditions + [{ 'type' => 'assignee', 'operator' => 'is_nobody' }],
             actions: [{ 'type' => 'set_assignee', 'mode' => 'user', 'user_id' => id(assignee) }])
      end

      def time_budget_exceeded
        rule('time_budget_exceeded', 'time_entry_logged',
             conditions: [{ 'type' => 'time_spent', 'operator' => 'gt_estimated' }],
             actions: [
               { 'type' => 'add_note', 'text' => l(:automation_rules_recipe_time_budget_exceeded_note) },
               { 'type' => 'add_watchers', 'who' => 'role', 'role_id' => id(role_named('Manager')) }
             ])
      end

      private

      def rule(key, trigger_type, trigger_options: {}, conditions: [], actions: [])
        {
          'name' => l("automation_rules_recipe_#{key}"),
          'description' => l("automation_rules_recipe_#{key}_description"),
          'trigger_type' => trigger_type,
          'trigger_options' => trigger_options,
          'conditions' => conditions,
          'actions' => actions
        }
      end

      def id(record)
        record&.id&.to_s
      end

      def status_named(name, closed:)
        IssueStatus.find_by(name: name) || IssueStatus.sorted.find_by(is_closed: closed) || IssueStatus.sorted.first
      end

      def priority_named(name)
        IssuePriority.active.find_by(name: name) || IssuePriority.default || IssuePriority.active.first
      end

      def role_named(name)
        Role.givable.find_by(name: name) || Role.givable.sorted.first
      end
    end
  end
end
