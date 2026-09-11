module RedmineAutomationRules
  module Actions
    class SetStatus < Base
      param 'value', widget: 'select', options: 'status', required: true

      def apply(issue, context)
        status = ::IssueStatus.find_by(id: param('value'))
        fail!(l(:automation_rules_error_status_not_found, id: param('value'))) unless status
        return if issue.status_id == status.id

        unless issue.new_statuses_allowed_to(author(context)).include?(status)
          fail!(l(:automation_rules_error_status_not_allowed, status: status.name, user: author(context).name))
        end
        issue.status = status
      end

      def describe
        l(:automation_rules_action_sentence_set_status, status: name_of(::IssueStatus, param('value')))
      end
    end
  end
end
