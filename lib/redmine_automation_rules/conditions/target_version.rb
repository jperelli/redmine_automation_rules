module RedmineAutomationRules
  module Conditions
    class TargetVersion < Base
      operators 'is', 'is_not', 'is_empty', 'is_set', 'is_closed', 'is_open'
      param 'value', widget: 'select', options: 'version', required: true, only_if: { operator: %w[is is_not] }

      def matches?(issue, _context = {})
        version = issue.fixed_version
        case operator
        when 'is_empty' then version.nil?
        when 'is_set' then version.present?
        when 'is_closed' then version.present? && version.closed?
        when 'is_open' then version.present? && version.open?
        else apply_negation(issue.fixed_version_id.to_s == value.to_s)
        end
      end

      def value_label
        operator.in?(%w[is is_not]) ? name_of(::Version, value) : nil
      end
    end
  end
end
