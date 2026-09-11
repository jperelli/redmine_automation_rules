module RedmineAutomationRules
  module Actions
    # Moves a closed issue back to an open status: the chosen one, or the
    # tracker's default status when allowed, or the first allowed open status.
    class ReopenIssue < Base
      param 'value', widget: 'select', options: 'status', label: :automation_rules_open_status_optional

      def apply(issue, context)
        return unless issue.closed?

        status = open_status_for(issue, context)
        fail!(l(:automation_rules_error_no_open_status)) unless status

        issue.status = status
      end

      def describe
        if param?('value')
          l(:automation_rules_action_sentence_reopen_issue_as, status: name_of(::IssueStatus, param('value')))
        else
          l(:automation_rules_action_sentence_reopen_issue)
        end
      end

      private

      def open_status_for(issue, context)
        allowed = issue.new_statuses_allowed_to(author(context)).reject(&:is_closed?)
        return allowed.find { |s| s.id.to_s == param('value').to_s } if param?('value')

        default = issue.tracker&.default_status
        allowed.include?(default) ? default : allowed.min_by(&:position)
      end
    end
  end
end
