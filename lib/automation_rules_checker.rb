# Evaluates the due scheduled rules against their candidate issues, records
# the run in AutomationRulesRun and returns how many rules were run. +source+
# tells the run log what triggered it (see AutomationRulesRun::SOURCES).
# Adapted from Redmine Periodic Task's ScheduledTasksChecker.
class AutomationRulesChecker
  # Counters and messages of one checker run.
  class Stats
    attr_reader :errors, :notes
    attr_accessor :rules_evaluated, :issues_matched, :actions_applied

    def initialize
      @rules_evaluated = 0
      @issues_matched = 0
      @actions_applied = 0
      @errors = []
      @notes = []
    end

    def record(rule, result)
      return unless result.matched?

      @issues_matched += 1
      @actions_applied += result.applied.size if result.success?
      @errors << "#{prefix(rule)} ##{result.issue.id}: #{result.error}" if result.error
    end

    def note(rule, message)
      @notes << "#{prefix(rule)} #{message}"
    end

    def error(rule, message)
      @errors << "#{prefix(rule)} #{message}"
    end

    private

    def prefix(rule)
      "#{rule.name} (##{rule.id}):"
    end
  end

  def self.check!(source: 'rake')
    now = Time.current
    stats = Stats.new
    rules = AutomationRule.active.scheduled.due_at(now).sorted.includes(:project, :author).to_a

    # Notes and descriptions render in the shell-configured locale (or
    # Redmine's default). The checker also runs inside web requests, so the
    # caller's locale must be restored afterwards.
    I18n.with_locale(ENV['LOCALE'] || I18n.default_locale) do
      rules.each do |rule|
        run_rule(rule, now, stats)
      rescue ActiveRecord::RecordNotFound
        # Deleted since the query above; anything else missing is a real error.
        raise if AutomationRule.exists?(rule.id)

        Rails.logger.info "[automation_rules] checker: rule ##{rule.id} was deleted before it could run"
      rescue StandardError => e
        # The transaction rolled back: no issue changed, no schedule change.
        # The rule keeps the error and the other due rules still run.
        Rails.logger.error "[automation_rules] checker: rule ##{rule.id}: #{e.class}: #{e.message}"
        stats.error(rule, "#{e.class}: #{e.message}")
        rule.update_columns(last_error: "#{e.class}: #{e.message}")
      end
    end
    rules.size
  rescue StandardError => e
    stats.errors << "#{e.class}: #{e.message}"
    raise
  ensure
    record_run(source, now, stats)
  end

  # One rule's occurrence, as a unit: cron, the web scheduler, the endpoint and
  # "Run checker now" can fire together, so the row is locked (with_lock:
  # transaction + SELECT FOR UPDATE) from evaluating the issues until the next
  # run time is saved. lock! reloads the rule, so a rule another trigger just
  # ran is seen as no longer due and skipped; a failure anywhere rolls every
  # issue change of this occurrence back along with the schedule.
  def self.run_rule(rule, now, stats)
    rule.with_lock do
      next unless rule.due?(now)

      if rule.project && !rule.project.module_enabled?(:automation_rules)
        stats.note(rule, I18n.t(:automation_rules_checker_module_disabled, project: rule.project.name))
      else
        stats.rules_evaluated += 1
        matched = evaluate(rule, now, stats)
        stats.note(rule, I18n.t(:automation_rules_checker_issues_matched, count: matched))
      end
      rule.finish_scheduled_run!(now)
    end
  end
  private_class_method :run_rule

  def self.evaluate(rule, now, stats)
    matched = 0
    rule.candidate_issues.find_each do |issue|
      runner = RedmineAutomationRules::Runner.new(rule, issue, trigger: 'scheduled', context: { scheduled_at: now })
      result = runner.run
      stats.record(rule, result)
      matched += 1 if result.matched?
    end
    matched
  end
  private_class_method :evaluate

  def self.record_run(source, now, stats)
    AutomationRulesRun.record!(source: source, started_at: now, finished_at: Time.current,
                               rules_evaluated: stats.rules_evaluated, issues_matched: stats.issues_matched,
                               actions_applied: stats.actions_applied, errors: stats.errors, notes: stats.notes)
  rescue StandardError => e
    Rails.logger.error "[automation_rules] checker: could not record run: #{e.class}: #{e.message}"
  end
  private_class_method :record_run
end
