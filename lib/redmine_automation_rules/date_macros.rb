module RedmineAutomationRules
  # Date macros in the style of Periodic-Task, usable in notes, custom field
  # values, subjects and templates:
  #
  #   **DAY** **MONTH** **MONTHNAME** **YEAR** **WEEK** **WEEKISO**
  #   **WEEKISO_YEAR** **QUARTER**, each with an optional day offset (**DAY+7**,
  #   **MONTH-1**), plus **NEXT_WEEK**, **NEXT_MONTH**, **PREVIOUS_MONTH** and
  #   their *_YEAR / MONTHNAME companions. **DATE** and **DATE+N** render the
  #   full ISO date, which is what date custom fields and date columns expect.
  module DateMacros
    DATE_MACRO = /\*\*(DATE|DAY|WEEKISO_YEAR|WEEKISO|WEEK|QUARTER|MONTHNAME|MONTH|YEAR)([+-]\d{1,4})?\*\*/

    SHIFTED_MACROS = {
      'NEXT_WEEK' => [1.week, 'WEEK'], 'NEXT_WEEK_YEAR' => [1.week, 'YEAR'],
      'NEXT_WEEKISO' => [1.week, 'WEEKISO'], 'NEXT_WEEKISO_YEAR' => [1.week, 'WEEKISO_YEAR'],
      'NEXT_MONTH' => [1.month, 'MONTH'], 'NEXT_MONTHNAME' => [1.month, 'MONTHNAME'],
      'NEXT_MONTH_YEAR' => [1.month, 'YEAR'],
      'PREVIOUS_MONTH' => [-1.month, 'MONTH'], 'PREVIOUS_MONTHNAME' => [-1.month, 'MONTHNAME'],
      'PREVIOUS_MONTH_YEAR' => [-1.month, 'YEAR']
    }.freeze
    SHIFTED_MACRO = /\*\*(#{SHIFTED_MACROS.keys.sort_by { |k| -k.length }.join('|')})\*\*/

    module_function

    def apply(text, today = User.current.today)
      return text unless text.is_a?(String) && text.include?('**')

      shifted = text.gsub(SHIFTED_MACRO) do
        shift, component = SHIFTED_MACROS.fetch(Regexp.last_match(1))
        value(component, today + shift)
      end
      shifted.gsub(DATE_MACRO) { value(Regexp.last_match(1), today + Regexp.last_match(2).to_i.days) }
    end

    def value(name, date)
      case name
      when 'DATE' then date.strftime('%Y-%m-%d')
      when 'DAY' then date.strftime('%d')
      when 'WEEKISO' then date.strftime('%V')
      when 'WEEKISO_YEAR' then date.strftime('%G')
      when 'WEEK' then date.strftime('%W')
      when 'QUARTER' then (((date.month - 1) / 3) + 1).to_s
      when 'MONTHNAME' then ::I18n.localize(date, format: '%B')
      when 'MONTH' then date.strftime('%m')
      when 'YEAR' then date.strftime('%Y')
      end
    end
  end
end
