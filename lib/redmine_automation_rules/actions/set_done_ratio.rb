module RedmineAutomationRules
  module Actions
    class SetDoneRatio < Base
      param 'value', widget: 'number', required: true, placeholder: :automation_rules_placeholder_percent

      def apply(issue, _context)
        ratio = param('value').to_i.clamp(0, 100)
        issue.done_ratio = ratio
      end

      def describe
        l(:automation_rules_action_sentence_set_done_ratio, ratio: param('value').to_i.clamp(0, 100))
      end
    end
  end
end
