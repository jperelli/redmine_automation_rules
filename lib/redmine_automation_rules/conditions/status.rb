module RedmineAutomationRules
  module Conditions
    class Status < Base
      operators 'is', 'is_not', 'is_closed', 'is_open'
      param 'value', widget: 'select', options: 'status', required: true, only_if: { operator: %w[is is_not] }

      def matches?(issue, _context = {})
        case operator
        when 'is_closed' then issue.closed?
        when 'is_open' then !issue.closed?
        else apply_negation(issue.status_id.to_s == value.to_s)
        end
      end

      def value_label
        operator.in?(%w[is is_not]) ? name_of(::IssueStatus, value) : nil
      end
    end
  end
end
