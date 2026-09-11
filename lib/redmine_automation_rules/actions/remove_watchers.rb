module RedmineAutomationRules
  module Actions
    class RemoveWatchers < Base
      param 'who', widget: 'select', required: true,
                   options: %w[user author assignee current_user role group all].map do |w|
                     [:"automation_rules_who_#{w}", w]
                   end
      param 'user_id', widget: 'select', options: 'user', required: true, only_if: { who: 'user' }
      param 'role_id', widget: 'select', options: 'role', required: true, only_if: { who: 'role' }
      param 'group_id', widget: 'select', options: 'group', required: true, only_if: { who: 'group' }

      def apply(issue, context)
        users = param('who') == 'all' ? issue.watcher_users.to_a : resolve_users(param('who'), issue, context)
        users.each { |user| issue.remove_watcher(user) }
      end

      def modifies_issue?
        false
      end

      def describe
        l(:automation_rules_action_sentence_remove_watchers, who: who_label)
      end
    end
  end
end
