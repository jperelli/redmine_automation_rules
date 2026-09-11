module RedmineAutomationRules
  module Actions
    class SetTargetVersion < Base
      modes 'version', 'clear'
      param 'value', widget: 'select', options: 'version', required: true, only_if: { mode: 'version' }

      def apply(issue, _context)
        if mode == 'clear'
          issue.fixed_version = nil
          return
        end

        version = issue.assignable_versions.find { |v| v.id.to_s == param('value').to_s }
        fail!(l(:automation_rules_error_version_not_assignable, id: param('value'))) unless version

        issue.fixed_version = version
      end

      def describe
        return l(:automation_rules_action_sentence_clear_target_version) if mode == 'clear'

        l(:automation_rules_action_sentence_set_target_version, version: name_of(::Version, param('value')))
      end
    end
  end
end
