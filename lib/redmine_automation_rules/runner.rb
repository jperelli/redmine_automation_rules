module RedmineAutomationRules
  # Evaluates one rule against one issue: checks the conditions, applies the
  # actions in order as the rule's author, saves the issue once (one journal),
  # then performs post-save side effects. Nothing raises out of #run: errors
  # are captured in the returned Result and recorded on the rule.
  #
  #   result = Runner.new(rule, issue, trigger: 'issue_updated').run
  #   result.matched?  result.applied  result.error
  #
  # With +dry_run: true+ the whole thing runs inside a rolled back transaction
  # and the result lists the changes that would have been saved.
  class Runner
    Result = Struct.new(:rule, :issue, :trigger, :dry_run, :conditions, :matched, :applied, :changes, :notes, :error,
                        keyword_init: true) do
      def matched?
        matched
      end

      def success?
        error.nil?
      end

      def applied_summary
        applied.join(', ')
      end
    end

    class Rollback < StandardError; end

    attr_reader :rule, :issue, :trigger, :context

    def initialize(rule, issue, trigger: nil, dry_run: false, context: {})
      @rule = rule
      @issue = issue
      @trigger = trigger || rule.trigger_type
      @dry_run = dry_run
      @context = { rule: rule, issue: issue, trigger: @trigger, dry_run: dry_run, user: rule.author }.merge(context)
    end

    def dry_run?
      @dry_run
    end

    def run
      result = Result.new(rule: rule, issue: issue, trigger: trigger, dry_run: dry_run?, conditions: [], applied: [],
                          changes: {}, notes: nil, matched: false)
      as_user(rule.author) do
        result.matched = evaluate_conditions(result)
        execute_actions(result) if result.matched
      end
      result
    rescue StandardError => e
      Rails.logger.error("[automation_rules] rule ##{rule.id} on issue ##{issue.id}: #{e.class}: #{e.message}")
      result.error = "#{e.class}: #{e.message}"
      result
    ensure
      rule.record_run!(result&.error) if result&.matched && !dry_run?
    end

    private

    def evaluate_conditions(result)
      rule.condition_objects.each do |condition|
        matched = begin
          condition.matches?(issue, context)
        rescue StandardError => e
          raise ActionError,
                l(:automation_rules_error_condition_failed, condition: condition.describe, message: e.message)
        end
        result.conditions << { condition: condition, description: condition.describe, matched: matched }
      end
      result.conditions.all? { |c| c[:matched] }
    end

    def execute_actions(result)
      actions = rule.action_objects
      run_in_transaction do
        prepare_journal
        actions.each do |action|
          action.apply(issue, context)
          result.applied << action.describe
        end
        append_note_marker
        result.changes = issue_changes
        result.notes = issue.current_journal&.notes.presence
        save_issue! if issue_modified?
        raise Rollback if dry_run?
      end
      return if dry_run?

      actions.each { |action| action.perform(issue, context) }
    rescue Rollback
      issue.reload
    end

    def run_in_transaction(&)
      Issue.transaction(requires_new: true, &)
    end

    def prepare_journal
      issue.clear_journal if issue.respond_to?(:clear_journal)
      issue.init_journal(rule.author)
    end

    def append_note_marker
      journal = issue.current_journal
      return unless journal && journal.notes.present? && rule.note_marker

      journal.notes = "#{journal.notes.chomp}\n\n_(#{l(:automation_rules_note_marker, name: rule.name)})_"
    end

    def issue_changes
      changes = issue.changes.except('updated_on', 'lock_version', 'closed_on')
      custom = issue.custom_field_values.select { |v| custom_value_changed?(v) }.to_h do |v|
        [v.custom_field.name, [v.value_was, v.value]]
      end
      changes.merge(custom)
    end

    def custom_value_changed?(custom_value)
      before = custom_value.value_was
      after = custom_value.value
      before != after && !(before.blank? && after.blank?)
    end

    def issue_modified?
      issue.changed? || issue.custom_field_values.any? do |v|
        custom_value_changed?(v)
      end || issue.current_journal&.notes.present?
    end

    def save_issue!
      return if issue.save

      raise ActionError, issue.errors.full_messages.to_sentence
    end

    def as_user(user)
      previous = User.current
      User.current = user || User.anonymous
      yield
    ensure
      User.current = previous
    end

    def l(*, **)
      ::I18n.t(*, **)
    end
  end
end
