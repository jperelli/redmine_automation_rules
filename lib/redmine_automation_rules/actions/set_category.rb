module RedmineAutomationRules
  module Actions
    class SetCategory < Base
      modes 'category', 'clear'
      param 'value', widget: 'select', options: 'category', required: true, only_if: { mode: 'category' }

      def apply(issue, _context)
        if mode == 'clear'
          issue.category = nil
          return
        end

        category = issue.project.issue_categories.find_by(id: param('value'))
        fail!(l(:automation_rules_error_record_not_found, type: l(:field_category), id: param('value'))) unless category

        issue.category = category
      end

      def describe
        return l(:automation_rules_action_sentence_clear_category) if mode == 'clear'

        l(:automation_rules_action_sentence_set_category, category: name_of(::IssueCategory, param('value')))
      end
    end
  end
end
