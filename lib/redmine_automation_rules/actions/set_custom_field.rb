module RedmineAutomationRules
  module Actions
    # Sets a custom field. Text values go through {{variables}} and date
    # macros (**DATE**, **DAY**...). User fields also accept author, assignee
    # and current_user. Issues whose tracker or project does not have the
    # field are skipped.
    class SetCustomField < Base
      USER_ALIASES = %w[author assignee current_user].freeze

      param 'custom_field_id', widget: 'select', options: 'custom_field', required: true
      param 'value', widget: 'custom_field_value', placeholder: :automation_rules_custom_field_value_placeholder

      def custom_field
        @custom_field ||= ::IssueCustomField.find_by(id: param('custom_field_id'))
      end

      def apply(issue, context)
        fail!(l(:automation_rules_error_custom_field_not_found, id: param('custom_field_id'))) unless custom_field
        return unless issue.available_custom_fields.include?(custom_field)

        issue.custom_field_values = { custom_field.id => resolved_value(issue, context) }
      end

      def describe
        field = custom_field&.name || "##{param('custom_field_id')}"
        l(:automation_rules_action_sentence_set_custom_field, field: field, value: param('value').to_s)
      end

      private

      def resolved_value(issue, context)
        raw = param('value')
        return '' if raw.blank?

        if custom_field.field_format == 'user' && USER_ALIASES.include?(raw.to_s)
          return resolve_users(raw, issue, context).first&.id.to_s
        end

        value = substitute(raw, issue, context)
        custom_field.multiple? ? value.split(',').map(&:strip).compact_blank : value
      end
    end
  end
end
