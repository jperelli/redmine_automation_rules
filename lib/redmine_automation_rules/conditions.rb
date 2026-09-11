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

      private

      # Applies an equality operator (is / is_not) to the given comparison.
      def apply_negation(result)
        operator.to_s.end_with?('_not') || operator.to_s.start_with?('not_') ? !result : result
      end
    end
  end
end

Dir[File.join(__dir__, 'conditions', '*.rb')].each { |file| require file }
