module RedmineAutomationRules
  module Conditions
    class Tracker < Base
      operators 'is', 'is_not'
      param 'value', widget: 'select', options: 'tracker', required: true

      def matches?(issue, _context = {})
        apply_negation(issue.tracker_id.to_s == value.to_s)
      end

      def value_label
        name_of(::Tracker, value)
      end
    end
  end
end
