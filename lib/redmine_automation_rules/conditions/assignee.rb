module RedmineAutomationRules
  module Conditions
    class Assignee < Base
      operators 'is', 'is_not', 'is_nobody', 'is_anybody', 'is_author', 'is_current_user', 'in_group', 'not_in_group'
      param 'value', widget: 'select', options: 'user', required: true, only_if: { operator: %w[is is_not] }
      param 'group_id', widget: 'select', options: 'group', required: true,
                        only_if: { operator: %w[in_group not_in_group] }

      def matches?(issue, context = {})
        assignee = issue.assigned_to
        case operator
        when 'is_nobody' then assignee.nil?
        when 'is_anybody' then assignee.present?
        when 'is_author' then assignee.present? && assignee == issue.author
        when 'is_current_user' then assignee.present? && assignee == actor(context)
        when 'in_group' then group_includes?(assignee, param('group_id'))
        when 'not_in_group' then !group_includes?(assignee, param('group_id'))
        else apply_negation(issue.assigned_to_id.to_s == value.to_s)
        end
      end

      def value_label
        case operator
        when 'is', 'is_not' then name_of(::Principal, value)
        when 'in_group', 'not_in_group' then name_of(::Group, param('group_id'))
        end
      end
    end
  end
end
