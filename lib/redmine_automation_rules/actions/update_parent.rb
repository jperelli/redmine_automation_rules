module RedmineAutomationRules
  module Actions
    # Applies one action to the parent issue after the issue was saved, e.g.
    # "close the parent when all subtasks are closed". Issues without a
    # parent are skipped.
    class UpdateParent < Base
      SUB_ACTIONS = %w[close_issue reopen_issue set_status set_done_ratio set_priority add_note].freeze

      param 'action', widget: 'select', required: true,
                      options: SUB_ACTIONS.map { |a| [:"automation_rules_action_#{a}", a] }
      param 'value', widget: 'select', options: 'status', required: true, only_if: { action: 'set_status' }
      param 'ratio', widget: 'number', required: true, placeholder: :automation_rules_placeholder_percent,
                     only_if: { action: 'set_done_ratio' }
      param 'priority_id', widget: 'select', options: 'priority', required: true, only_if: { action: 'set_priority' }
      param 'text', widget: 'textarea', required: true, placeholder: :automation_rules_note_placeholder,
                    only_if: { action: 'add_note' }

      def modifies_issue?
        false
      end

      # With +issue+ and +context+ the note text is rendered against the
      # subtask first, so {{issue.*}} refers to the issue that triggered the rule.
      def sub_action(issue = nil, context = nil)
        row = sub_action_row
        row['text'] = substitute(row['text'], issue, context) if issue && row.key?('text')
        Actions.build(row)
      end

      def validate
        errors = super
        errors.concat(sub_action.validate) if sub_action
        errors
      end

      def perform(issue, context)
        parent = issue.parent
        action = sub_action(issue, context)
        return unless parent && action

        parent.init_journal(author(context))
        action.apply(parent, context)
        Runner.append_note_marker(parent, rule(context))
        fail!(parent.errors.full_messages.to_sentence) unless parent.save

        action.perform(parent, context)
      end

      def describe
        l(:automation_rules_action_sentence_update_parent, action: sub_action&.describe || param('action').to_s)
      end

      private

      def sub_action_row
        case param('action')
        when 'set_status' then { 'type' => 'set_status', 'value' => param('value') }
        when 'set_done_ratio' then { 'type' => 'set_done_ratio', 'value' => param('ratio') }
        when 'set_priority' then { 'type' => 'set_priority', 'value' => param('priority_id') }
        when 'add_note' then { 'type' => 'add_note', 'text' => param('text') }
        when 'close_issue', 'reopen_issue' then { 'type' => param('action') }
        else {}
        end
      end
    end
  end
end
