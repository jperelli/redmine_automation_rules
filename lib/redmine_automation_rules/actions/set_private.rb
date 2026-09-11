module RedmineAutomationRules
  module Actions
    class SetPrivate < Base
      param 'value', widget: 'select', options: 'boolean', required: true

      def apply(issue, _context)
        issue.is_private = private?
      end

      def describe
        private? ? l(:automation_rules_action_sentence_make_private) : l(:automation_rules_action_sentence_make_public)
      end

      private

      def private?
        param('value').to_s == '1'
      end
    end
  end
end
