module RedmineAutomationRules
  module Conditions
    class Description < Base
      operators 'contains', 'not_contains', 'starts_with', 'matches', 'not_matches', 'is', 'is_not'
      param 'value', widget: 'text', required: true, placeholder: :automation_rules_placeholder_text

      def matches?(issue, _context = {})
        text_matches?(issue.description)
      end

      def value_label
        %("#{value}")
      end
    end
  end
end
