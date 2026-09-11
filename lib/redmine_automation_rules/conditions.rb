module RedmineAutomationRules
  # Registry of condition types. Each type is one class under
  # lib/redmine_automation_rules/conditions/ implementing #matches?(issue, context).
  module Conditions
    def self.registry
      @registry ||= {}
    end

    def self.register(klass)
      registry[klass.key] = klass
    end

    def self.all
      registry.values
    end

    def self.[](key)
      registry[key.to_s]
    end

    # Builds a condition object from a stored row ({'type' => 'tracker', ...}),
    # nil for unknown types.
    def self.build(row)
      return nil unless row.is_a?(Hash)

      klass = registry[row['type'].to_s]
      klass&.new(row)
    end

    def self.schema(project = nil)
      all.map { |klass| klass.schema(project) }
    end

    # Evaluates a row against an issue; unknown types never match.
    def self.matches?(row, issue, context = {})
      condition = build(row)
      condition.present? && condition.matches?(issue, context)
    end

    class Base
      include Definition

      def self.i18n_prefix
        'automation_rules_condition'
      end

      # Operators offered by the type, as an inline options list for the form.
      def self.operators(*ops)
        if ops.empty?
          @operators || []
        else
          @operators = ops.map(&:to_s)
          param 'operator', widget: 'select', options: @operators.map { |op| [:"automation_rules_operator_#{op}", op] }
        end
      end

      def self.inherited(subclass)
        super
        Conditions.register(subclass)
      end

      def operator
        op = param('operator').to_s
        self.class.operators.include?(op) ? op : self.class.operators.first
      end

      def value
        param('value')
      end

      def matches?(_issue, _context = {})
        raise NotImplementedError
      end

      # "tracker is Bug"
      def describe
        [label.downcase, l("automation_rules_operator_#{operator}"), value_label].compact_blank.join(' ')
      end

      def value_label
        value.to_s
      end

      def validate
        errors = super
        errors << l(:automation_rules_error_invalid_regexp, message: regexp_error) if regexp_error
        errors
      end

      private

      def regexp_error
        return nil unless operator.in?(%w[matches not_matches]) && param?('value')

        Regexp.new(value.to_s)
        nil
      rescue RegexpError => e
        e.message
      end

      # Applies an equality operator (is / is_not) to the given comparison.
      def apply_negation(result)
        operator.to_s.end_with?('_not') || operator.to_s.start_with?('not_') ? !result : result
      end

      # The user who caused the event (before the runner switched to the rule
      # author), falling back to the author for scheduled and manual runs.
      def actor(context)
        context[:actor].presence || context[:user] || User.current
      end

      def today
        User.current.today
      end

      def days
        param('days').to_i
      end

      # Compares +actual+ with +expected+ using a numeric operator name.
      def compares?(actual, expected, oper = operator)
        return false if actual.nil? || expected.nil?

        case oper
        when 'eq', 'is' then actual == expected
        when 'is_not' then actual != expected
        when 'gt' then actual > expected
        when 'gte' then actual >= expected
        when 'lt' then actual < expected
        when 'lte' then actual <= expected
        else false
        end
      end

      def text_matches?(text, oper = operator, pattern = value.to_s)
        text = text.to_s
        case oper
        when 'contains' then text.downcase.include?(pattern.downcase)
        when 'not_contains' then !text.downcase.include?(pattern.downcase)
        when 'starts_with' then text.downcase.start_with?(pattern.downcase)
        when 'is' then text.strip.casecmp?(pattern.strip)
        when 'is_not' then !text.strip.casecmp?(pattern.strip)
        when 'matches' then Regexp.new(pattern, Regexp::IGNORECASE).match?(text)
        when 'not_matches' then !Regexp.new(pattern, Regexp::IGNORECASE).match?(text)
        else false
        end
      end

      # Date operators shared by due/start date and date custom fields.
      def date_matches?(date, oper = operator)
        case oper
        when 'is_empty' then date.nil?
        when 'is_set' then !date.nil?
        when 'is_past' then date.present? && date < today
        when 'is_today' then date == today
        when 'within_days' then date.present? && date >= today && date <= today + days
        when 'more_than_days_ago' then date.present? && date < today - days
        when 'more_than_days_ahead' then date.present? && date > today + days
        else false
        end
      end

      def group_includes?(user, group_id)
        return false unless user.is_a?(::User)

        user.group_ids.include?(group_id.to_i)
      end
    end
  end
end

Dir[File.join(__dir__, 'conditions', '*.rb')].each { |file| require file }
