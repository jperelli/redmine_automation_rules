module RedmineAutomationRules
  module Conditions
    class Parent < Base
      operators 'has_parent', 'no_parent', 'parent_is_closed', 'parent_is_open', 'siblings_closed'

      def matches?(issue, _context = {})
        parent = issue.parent
        case operator
        when 'has_parent' then parent.present?
        when 'no_parent' then parent.nil?
        when 'parent_is_closed' then parent.present? && parent.closed?
        when 'parent_is_open' then parent.present? && !parent.closed?
        when 'siblings_closed' then parent.present? && siblings_closed?(issue, parent)
        else false
        end
      end

      def value_label
        nil
      end

      private

      # The issue and every other subtask of its parent are closed.
      def siblings_closed?(issue, parent)
        parent.children.where.not(id: issue.id).to_a.all?(&:closed?) && issue.closed?
      end
    end
  end
end
