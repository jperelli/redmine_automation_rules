module RedmineAutomationRules
  module Conditions
    class WatchersCount < Base
      operators 'eq', 'lt', 'gt', 'lte', 'gte'
      param 'value', widget: 'number', required: true

      def matches?(issue, _context = {})
        compares?(issue.watcher_users.count, value.to_i)
      end
    end
  end
end
