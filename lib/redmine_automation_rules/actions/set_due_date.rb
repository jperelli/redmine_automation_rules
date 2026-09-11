require_relative 'date_setting'

module RedmineAutomationRules
  module Actions
    class SetDueDate < Base
      include DateSetting

      def attribute
        'due_date'
      end

      def other_attribute
        'start_date'
      end
    end
  end
end
