module RedmineAutomationRules
  module Conditions
    # One condition type for every issue custom field format. The operator list
    # is the union of what the formats support; the value widget follows the
    # selected field's format (list/user/version/bool => select, date, number).
    class CustomField < Base
      operators 'is', 'is_not', 'is_empty', 'is_set', 'contains', 'not_contains', 'matches',
                'gt', 'lt', 'gte', 'lte',
                'is_past', 'is_today', 'within_days', 'more_than_days_ago', 'more_than_days_ahead',
                'is_current_user', 'is_author', 'is_assignee'
      param 'custom_field_id', widget: 'select', options: 'custom_field', required: true
      param 'value', widget: 'custom_field_value', required: true,
                     only_if: { operator: %w[is is_not contains not_contains matches gt lt gte lte] }
      param 'days', widget: 'number', required: true, placeholder: :automation_rules_placeholder_days,
                    only_if: { operator: %w[within_days more_than_days_ago more_than_days_ahead] }

      def custom_field
        @custom_field ||= ::IssueCustomField.find_by(id: param('custom_field_id'))
      end

      def matches?(issue, context = {})
        return false unless custom_field
        return false unless issue.available_custom_fields.include?(custom_field)

        values = raw_values(issue)
        case operator
        when 'is_empty' then values.empty?
        when 'is_set' then values.any?
        when 'is', 'is_not' then apply_negation(values.any? { |v| same_value?(v) })
        when 'contains', 'not_contains', 'matches'
          text = values.map { |v| custom_field.format.formatted_value(nil, custom_field, v, issue, false) }.join(' ')
          text_matches?(text)
        when 'gt', 'lt', 'gte', 'lte' then values.any? { |v| compares_typed?(v) }
        when 'is_past', 'is_today', 'within_days', 'more_than_days_ago', 'more_than_days_ahead'
          values.any? { |v| date_matches?(parse_date(v)) }
        when 'is_current_user' then values.include?(actor(context).id.to_s)
        when 'is_author' then values.include?(issue.author_id.to_s)
        when 'is_assignee' then issue.assigned_to_id.present? && values.include?(issue.assigned_to_id.to_s)
        else false
        end
      end

      def label
        custom_field ? custom_field.name : super
      end

      def describe
        [label, l("automation_rules_operator_#{operator}"), value_label].compact_blank.join(' ')
      end

      def value_label
        case operator
        when 'is', 'is_not', 'contains', 'not_contains', 'matches', 'gt', 'lt', 'gte', 'lte'
          custom_field ? custom_field.format.formatted_value(nil, custom_field, value, nil, false).to_s : value.to_s
        when 'within_days', 'more_than_days_ago', 'more_than_days_ahead'
          l(:automation_rules_n_days, count: days)
        end
      end

      def validate
        errors = super
        errors << l(:automation_rules_error_custom_field_not_found) if param?('custom_field_id') && custom_field.nil?
        errors
      end

      private

      def raw_values(issue)
        Array(issue.custom_field_value(custom_field)).map(&:to_s).compact_blank
      end

      def same_value?(stored)
        case custom_field.field_format
        when 'bool' then truthy?(stored) == truthy?(value)
        when 'int' then stored.to_i == value.to_i
        when 'float' then (stored.to_f - value.to_f).abs < Float::EPSILON
        when 'date' then parse_date(stored) == parse_date(value)
        else stored.to_s.strip.casecmp?(value.to_s.strip)
        end
      end

      def compares_typed?(stored)
        case custom_field.field_format
        when 'int' then compares?(stored.to_i, value.to_i)
        when 'float' then compares?(stored.to_f, value.to_f)
        when 'date' then compares?(parse_date(stored), parse_date(value))
        else compares?(stored.to_s, value.to_s)
        end
      end

      def truthy?(raw)
        %w[1 true yes].include?(raw.to_s.strip.downcase)
      end

      def parse_date(raw)
        raw.is_a?(Date) ? raw : Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
