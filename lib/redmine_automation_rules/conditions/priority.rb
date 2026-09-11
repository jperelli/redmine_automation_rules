module RedmineAutomationRules
  module Conditions
    class Priority < Base
      operators 'is', 'is_not', 'is_at_least', 'is_at_most'
      param 'value', widget: 'select', options: 'priority', required: true

      def matches?(issue, _context = {})
        case operator
        when 'is_at_least', 'is_at_most'
          target = ::IssuePriority.find_by(id: value)
          return false unless target && issue.priority

          if operator == 'is_at_least'
            issue.priority.position >= target.position
          else
            issue.priority.position <= target.position
          end
        else
          apply_negation(issue.priority_id.to_s == value.to_s)
        end
      end

      def value_label
        name_of(::IssuePriority, value)
      end
    end
  end
end
