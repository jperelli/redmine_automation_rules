module RedmineAutomationRules
  module Actions
    # Creates a subtask or a related issue from a template, after the issue
    # was saved. Subject and description accept {{variables}} and date macros.
    class CreateIssue < Base
      modes 'subtask', 'related'
      param 'relation_type', widget: 'select', options: 'relation_type', required: true, only_if: { mode: 'related' }
      param 'tracker_id', widget: 'select', options: 'tracker', label: :field_tracker
      param 'subject', widget: 'text', required: true, placeholder: :automation_rules_subject_placeholder
      param 'description', widget: 'textarea', placeholder: :automation_rules_description_placeholder
      param 'who', widget: 'select', label: :field_assigned_to,
                   options: %w[none user author assignee current_user].map { |w| [:"automation_rules_who_#{w}", w] }
      param 'user_id', widget: 'select', options: 'user', required: true, only_if: { who: 'user' }

      def modifies_issue?
        false
      end

      def perform(issue, context)
        new_issue = build_issue(issue, context)
        fail!(new_issue.errors.full_messages.to_sentence) unless new_issue.save

        return unless mode == 'related'

        relation = ::IssueRelation.new(issue_from: new_issue, issue_to: issue, relation_type: param('relation_type'))
        fail!(relation.errors.full_messages.to_sentence) unless relation.save
      end

      def describe
        subject = param('subject').to_s.truncate(40)
        if mode == 'subtask'
          l(:automation_rules_action_sentence_create_subtask, subject: subject)
        else
          l(:automation_rules_action_sentence_create_related, subject: subject, relation: relation_label)
        end
      end

      private

      def relation_label
        name = ::IssueRelation::TYPES.dig(param('relation_type'), :name)
        name ? l(name).downcase : param('relation_type').to_s
      end

      def build_issue(issue, context)
        new_issue = ::Issue.new(project: issue.project, author: author(context))
        new_issue.tracker = ::Tracker.find_by(id: param('tracker_id')) || issue.tracker
        new_issue.status = new_issue.tracker&.default_status || ::IssueStatus.sorted.first
        new_issue.priority = issue.priority
        new_issue.subject = substitute(param('subject'), issue, context).truncate(255)
        new_issue.description = substitute(param('description'), issue, context)
        new_issue.parent_issue_id = issue.id if mode == 'subtask'
        new_issue.is_private = issue.is_private
        assignee = resolve_users(param('who'), issue, context).first
        new_issue.assigned_to = assignee if assignee && new_issue.assignable_users.include?(assignee)
        new_issue
      end
    end
  end
end
