module RedmineAutomationRules
  # Working-day arithmetic that follows Redmine's own *Non-working days*
  # setting (Administration > Settings > Issue tracking), through the same
  # DateCalculation module Redmine uses for issue dates. Redmine memoizes the
  # setting per including object, so callers build a fresh instance for every
  # calculation instead of sharing one. Adapted from Periodic-Task.
  class WorkingDays
    include Redmine::Utils::DateCalculation

    def working_day?(date)
      !non_working_week_days.include?(date.cwday)
    end

    # Date of the first working day on or after +date+.
    def next_working_date(date)
      date += 1 until working_day?(date)
      date
    end

    # Date of the last working day on or before +date+.
    def previous_working_date(date)
      date -= 1 until working_day?(date)
      date
    end
  end
end
