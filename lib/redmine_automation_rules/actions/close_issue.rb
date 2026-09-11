module RedmineAutomationRules
  module Actions
    # Moves the issue to the first closed status the workflow allows the rule
    # author to use (or a chosen one). Idempotent: closed issues are left alone.
    class CloseIssue < Base
      param 'value', widget: 'select', options: 'status', label: :automation_rules_closed_status_optional

      def apply(issue, context)
        return if issue.closed?

        status = closed_status_for(issue, context)
        fail!(l(:automation_rules_error_no_closed_status)) unless status

        issue.status = status
      end

      def describe
        if param?('value')
          l(:automation_rules_action_sentence_close_issue_as, status: name_of(::IssueStatus, param('value')))
        else
          l(:automation_rules_action_sentence_close_issue)
        end
      end

      private

      def closed_status_for(issue, context)
        allowed = issue.new_statuses_allowed_to(author(context)).select(&:is_closed?)
        if param?('value')
          allowed.find { |s| s.id.to_s == param('value').to_s }
        else
          allowed.min_by(&:position)
        end
      end
    end
  end
end
