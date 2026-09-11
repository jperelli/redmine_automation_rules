module RedmineAutomationRules
  module Actions
    # Shared by SetDueDate and SetStartDate: an absolute date, today, a number
    # of days from today or from the other date of the issue, or clearing it,
    # optionally moved to the next working day (Redmine's non-working days).
    module DateSetting
      def self.included(base)
        base.modes 'date', 'today', 'relative', 'from_other_date', 'clear'
        base.param 'value', widget: 'date', required: true, only_if: { mode: 'date' }
        base.param 'days', widget: 'number', required: true, placeholder: :automation_rules_placeholder_days,
                           only_if: { mode: %w[relative from_other_date] }
        base.param 'only_if_empty', widget: 'checkbox', label: :automation_rules_only_if_empty
        base.param 'working_day', widget: 'checkbox', label: :automation_rules_shift_to_working_day
      end

      def apply(issue, _context)
        return if param('only_if_empty').to_s == '1' && issue.public_send(attribute).present?

        issue.public_send("#{attribute}=", target_date(issue))
      end

      def describe
        target = case mode
                 when 'date' then param('value').to_s
                 when 'today' then l(:automation_rules_mode_today)
                 when 'relative' then l(:automation_rules_days_from_today, count: param('days').to_i)
                 when 'from_other_date'
                   l(:automation_rules_days_from_date, count: param('days').to_i, date: other_attribute_label)
                 when 'clear' then l(:automation_rules_mode_clear)
                 end
        sentence = l(:automation_rules_action_sentence_set_date, field: attribute_label, value: target)
        sentence += " (#{l(:automation_rules_only_if_empty).downcase})" if param('only_if_empty').to_s == '1'
        sentence
      end

      private

      def target_date(issue)
        date = case mode
               when 'date' then parse(param('value'))
               when 'today' then User.current.today
               when 'relative' then User.current.today + param('days').to_i.days
               when 'from_other_date'
                 base = issue.public_send(other_attribute)
                 base && (base + param('days').to_i.days)
               end
        date = WorkingDays.new.next_working_date(date) if date && param('working_day').to_s == '1'
        date
      end

      def parse(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        fail!(l(:automation_rules_error_invalid_date, value: value))
      end

      def attribute_label
        l("field_#{attribute}").downcase
      end

      def other_attribute_label
        l("field_#{other_attribute}").downcase
      end
    end
  end
end
