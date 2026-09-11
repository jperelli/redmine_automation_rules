require_relative 'date_setting'

module RedmineAutomationRules
  module Actions
    class SetStartDate < Base
      include DateSetting

      def attribute
        'start_date'
      end

      def other_attribute
        'due_date'
      end
    end
  end
end
