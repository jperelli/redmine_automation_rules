module RedmineAutomationRules
  module Conditions
    class Category < Base
      operators 'is', 'is_not', 'is_empty', 'is_set'
      param 'value', widget: 'select', options: 'category', required: true, only_if: { operator: %w[is is_not] }

      def matches?(issue, _context = {})
        case operator
        when 'is_empty' then issue.category_id.nil?
        when 'is_set' then issue.category_id.present?
        else apply_negation(issue.category_id.to_s == value.to_s)
        end
      end

      def value_label
        operator.in?(%w[is is_not]) ? name_of(::IssueCategory, value) : nil
      end
    end
  end
end
