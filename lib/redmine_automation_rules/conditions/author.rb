module RedmineAutomationRules
  module Conditions
    class Author < Base
      operators 'is', 'is_not', 'is_current_user', 'in_group', 'not_in_group'
      param 'value', widget: 'select', options: 'user', required: true, only_if: { operator: %w[is is_not] }
      param 'group_id', widget: 'select', options: 'group', required: true,
                        only_if: { operator: %w[in_group not_in_group] }

      def matches?(issue, context = {})
        case operator
        when 'is_current_user' then issue.author == actor(context)
        when 'in_group' then group_includes?(issue.author, param('group_id'))
        when 'not_in_group' then !group_includes?(issue.author, param('group_id'))
        else apply_negation(issue.author_id.to_s == value.to_s)
        end
      end

      def value_label
        case operator
        when 'is', 'is_not' then name_of(::User, value)
        when 'in_group', 'not_in_group' then name_of(::Group, param('group_id'))
        end
      end
    end
  end
end
