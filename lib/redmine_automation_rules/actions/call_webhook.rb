module RedmineAutomationRules
  module Actions
    # POSTs a JSON payload describing the event and the issue to a URL, from a
    # background thread. With a secret the request carries the secret header
    # and an HMAC-SHA256 signature of the body.
    class CallWebhook < Base
      param 'url', widget: 'text', required: true, placeholder: :automation_rules_url_placeholder
      param 'secret', widget: 'text', label: :automation_rules_webhook_secret

      def modifies_issue?
        false
      end

      def perform(issue, context)
        Webhook.deliver(param('url'), payload(issue, context), secret: param('secret').presence)
      end

      def describe
        l(:automation_rules_action_sentence_call_webhook, url: param('url').to_s.truncate(60))
      end

      def payload(issue, context)
        {
          'event' => context[:trigger].to_s,
          'rule' => { 'id' => rule(context)&.id, 'name' => rule(context)&.name },
          'user' => { 'id' => actor(context).id, 'name' => actor(context).name },
          'timestamp' => Time.current.iso8601,
          'project' => { 'id' => issue.project.id, 'identifier' => issue.project.identifier,
                         'name' => issue.project.name },
          'issue' => issue_payload(issue)
        }
      end

      private

      def issue_payload(issue)
        {
          'id' => issue.id, 'subject' => issue.subject, 'description' => issue.description,
          'tracker' => issue.tracker&.name, 'status' => issue.status&.name, 'priority' => issue.priority&.name,
          'author' => issue.author&.name, 'assigned_to' => issue.assigned_to&.name,
          'category' => issue.category&.name, 'fixed_version' => issue.fixed_version&.name,
          'start_date' => issue.start_date&.to_s, 'due_date' => issue.due_date&.to_s,
          'done_ratio' => issue.done_ratio, 'estimated_hours' => issue.estimated_hours,
          'spent_hours' => issue.spent_hours, 'is_private' => issue.is_private,
          'parent_id' => issue.parent_id, 'created_on' => issue.created_on&.iso8601,
          'updated_on' => issue.updated_on&.iso8601, 'closed_on' => issue.closed_on&.iso8601,
          'url' => Substitution.issue_value(issue, 'url'),
          'custom_fields' => issue.custom_field_values.map do |v|
            { 'id' => v.custom_field_id, 'name' => v.custom_field.name, 'value' => v.value }
          end
        }
      end
    end
  end
end
