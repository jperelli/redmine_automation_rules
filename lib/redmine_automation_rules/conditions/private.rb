module RedmineAutomationRules
  module Conditions
    class Private < Base
      operators 'is_private', 'is_public'

      def matches?(issue, _context = {})
        operator == 'is_private' ? issue.is_private? : !issue.is_private?
      end

      def value_label
        nil
      end
    end
  end
end
