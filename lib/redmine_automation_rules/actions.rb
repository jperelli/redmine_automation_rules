module RedmineAutomationRules
  class ActionError < StandardError; end

  # Registry of action types. Each type is one class under
  # lib/redmine_automation_rules/actions/. An action changes the issue in
  # memory in #apply (the runner saves once, with a single journal, after all
  # actions ran) and/or does side effects in #perform, which runs after the
  # issue was saved (emails, webhooks, creating other issues).
  module Actions
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

    def self.build(row)
      return nil unless row.is_a?(Hash)

      klass = registry[row['type'].to_s]
      klass&.new(row)
    end

    def self.schema(project = nil)
      all.map { |klass| klass.schema(project) }
    end

    class Base
      include Definition

      def self.i18n_prefix
        'automation_rules_action'
      end

      def self.inherited(subclass)
        super
        Actions.register(subclass)
      end

      # Change +issue+ in memory. +context+ is the execution context (see Runner).
      def apply(issue, context); end

      # Side effects after the issue was saved. Not called on dry runs.
      def perform(issue, context); end

      # Changes the issue, so the runner has to save it after #apply.
      def modifies_issue?
        true
      end

      # "set status to Closed"
      def describe
        label.downcase
      end

      private

      def fail!(message)
        raise ActionError, message
      end

      def rule(context)
        context[:rule]
      end

      def author(context)
        context[:user] || rule(context)&.author || User.current
      end
    end
  end
end

Dir[File.join(__dir__, 'actions', '*.rb')].each { |file| require file }
