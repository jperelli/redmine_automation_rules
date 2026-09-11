module RedmineAutomationRules
  module Conditions
    class TimeSpent < Base
      operators 'gt_hours', 'lt_hours', 'gt_estimated', 'lte_estimated', 'none'
      param 'value', widget: 'number', required: true, placeholder: :automation_rules_placeholder_hours,
                     only_if: { operator: %w[gt_hours lt_hours] }

      def matches?(issue, _context = {})
        spent = issue.total_spent_hours.to_f
        case operator
        when 'gt_hours' then spent > value.to_f
        when 'lt_hours' then spent < value.to_f
        when 'gt_estimated' then estimated(issue).present? && spent > estimated(issue)
        when 'lte_estimated' then estimated(issue).present? && spent <= estimated(issue)
        when 'none' then spent.zero?
        else false
        end
      end

      def value_label
        operator.in?(%w[gt_hours lt_hours]) ? l_hours(value.to_f) : nil
      end

      private

      def estimated(issue)
        issue.total_estimated_hours
      end
    end
  end
end
