module RedmineAutomationRules
  module Conditions
    class StartDate < Base
      operators 'is_empty', 'is_set', 'is_past', 'is_today', 'within_days', 'more_than_days_ago', 'more_than_days_ahead'
      param 'days', widget: 'number', required: true, placeholder: :automation_rules_placeholder_days,
                    only_if: { operator: %w[within_days more_than_days_ago more_than_days_ahead] }

      def matches?(issue, _context = {})
        date_matches?(issue.start_date)
      end

      def value_label
        l(:automation_rules_n_days, count: days) if operator.in?(%w[within_days more_than_days_ago
                                                                    more_than_days_ahead])
      end
    end
  end
end
