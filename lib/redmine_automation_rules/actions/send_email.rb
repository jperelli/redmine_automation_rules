module RedmineAutomationRules
  module Actions
    # Emails users, members of a role or group, the watchers or plain
    # addresses with a subject and body template. Sent after the issue was
    # saved, through Redmine's mailer (so it follows the delivery settings).
    class SendEmail < Base
      RECIPIENTS = %w[user author assignee current_user role group watchers address].freeze

      param 'who', widget: 'select', required: true, options: RECIPIENTS.map { |w| [:"automation_rules_who_#{w}", w] }
      param 'user_id', widget: 'select', options: 'user', required: true, only_if: { who: 'user' }
      param 'role_id', widget: 'select', options: 'role', required: true, only_if: { who: 'role' }
      param 'group_id', widget: 'select', options: 'group', required: true, only_if: { who: 'group' }
      param 'addresses', widget: 'text', required: true, only_if: { who: 'address' },
                         placeholder: :automation_rules_addresses_placeholder
      param 'subject', widget: 'text', required: true, placeholder: :automation_rules_email_subject_placeholder
      param 'body', widget: 'textarea', required: true, placeholder: :automation_rules_email_body_placeholder

      def modifies_issue?
        false
      end

      def perform(issue, context)
        subject = substitute(param('subject'), issue, context)
        body = substitute(param('body'), issue, context)
        recipients(issue, context).each do |recipient|
          ::AutomationRulesMailer.deliver_rule_email(author(context), recipient, issue, subject, body)
        end
      end

      def describe
        l(:automation_rules_action_sentence_send_email, who: who_label)
      end

      private

      def recipients(issue, context)
        case param('who')
        when 'address' then param('addresses').to_s.split(/[,;\s]+/).compact_blank
        when 'watchers' then issue.watcher_users.select(&:active?)
        else resolve_users(param('who'), issue, context)
        end
      end

      def who_label(who = param('who'))
        who.to_s == 'address' ? param('addresses').to_s : super
      end
    end
  end
end
