module RedmineAutomationRules
  module Conditions
    class Subtasks < Base
      operators 'none', 'any', 'all_closed', 'any_open'

      def matches?(issue, _context = {})
        children = issue.children.to_a
        case operator
        when 'none' then children.empty?
        when 'any' then children.any?
        when 'all_closed' then children.any? && children.all?(&:closed?)
        when 'any_open' then children.any? { |child| !child.closed? }
        else false
        end
      end

      def value_label
        nil
      end
    end
  end
end
