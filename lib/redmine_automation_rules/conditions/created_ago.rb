module RedmineAutomationRules
  module Conditions
    class CreatedAgo < Base
      operators 'more_than_days', 'less_than_days', 'more_than_hours', 'less_than_hours'
      param 'value', widget: 'number', required: true

      def matches?(issue, _context = {})
        timestamp = issue.created_on
        return false if timestamp.nil?

        threshold = operator.end_with?('hours') ? value.to_f.hours : value.to_f.days
        age = Time.current - timestamp
        operator.start_with?('more_than') ? age > threshold : age < threshold
      end

      def value_label
        n = value.to_f
        n = n.to_i if n == n.to_i
        l(operator.end_with?('hours') ? :automation_rules_n_hours_ago : :automation_rules_n_days_ago, count: n)
      end
    end
  end
end
