module RedmineAutomationRules
  module Actions
    class SetPriority < Base
      param 'value', widget: 'select', options: 'priority', required: true

      def apply(issue, _context)
        priority = ::IssuePriority.find_by(id: param('value'))
        fail!(l(:automation_rules_error_record_not_found, type: l(:field_priority), id: param('value'))) unless priority

        issue.priority = priority
      end

      def describe
        l(:automation_rules_action_sentence_set_priority, priority: name_of(::IssuePriority, param('value')))
      end
    end
  end
end
