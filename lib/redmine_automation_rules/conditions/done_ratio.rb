module RedmineAutomationRules
  module Conditions
    class DoneRatio < Base
      operators 'eq', 'lt', 'gt', 'lte', 'gte'
      param 'value', widget: 'number', required: true, placeholder: :automation_rules_placeholder_percent

      def matches?(issue, _context = {})
        compares?(issue.done_ratio.to_i, value.to_i)
      end

      def value_label
        "#{value.to_i}%"
      end
    end
  end
end
