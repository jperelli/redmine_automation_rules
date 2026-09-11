module RedmineAutomationRules
  module Conditions
    class Parent < Base
      operators 'has_parent', 'no_parent', 'parent_is_closed', 'parent_is_open'

      def matches?(issue, _context = {})
        parent = issue.parent
        case operator
        when 'has_parent' then parent.present?
        when 'no_parent' then parent.nil?
        when 'parent_is_closed' then parent.present? && parent.closed?
        when 'parent_is_open' then parent.present? && !parent.closed?
        else false
        end
      end

      def value_label
        nil
      end
    end
  end
end
