require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesRunTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  def setup
    AutomationRule.delete_all
    AutomationRulesRun.delete_all
  end

  def record(source: 'web', rules_evaluated: 0, issues_matched: 0, actions_applied: 0, errors: [], notes: [],
             at: Time.current)
    AutomationRulesRun.record!(source: source, started_at: at, finished_at: at + 0.25,
                               rules_evaluated: rules_evaluated, issues_matched: issues_matched,
                               actions_applied: actions_applied, errors: errors, notes: notes)
  end

  def test_records_run_details
    run = record(source: 'endpoint', rules_evaluated: 2, issues_matched: 3, actions_applied: 4,
                 errors: ['Foo (#1): #7: boom'], notes: ['Foo (#1): 3 issues matched'])
    assert_equal 'endpoint', run.source
    assert_equal 2, run.rules_evaluated
    assert_equal 3, run.issues_matched
    assert_equal 4, run.actions_applied
    assert_equal 250, run.duration_ms
    assert_equal 'Foo (#1): #7: boom', run.error_messages
    assert_equal 'Foo (#1): 3 issues matched', run.notes
    assert_equal 1, run.runs_count
  end

  def test_source_must_be_known
    assert_raises(ActiveRecord::RecordInvalid) { record(source: 'cron') }
  end

  def test_consecutive_noop_runs_from_same_source_are_coalesced
    t = Time.current.change(usec: 0)
    first = record(at: t)
    record(at: t + 5.minutes)
    record(at: t + 10.minutes)
    assert_equal 1, AutomationRulesRun.count
    first.reload
    assert_equal 3, first.runs_count
    assert_equal t, first.started_at
    assert_equal t + 10.minutes, first.last_run_at
    assert first.noop?
  end

  def test_runs_that_evaluated_rules_without_changes_are_coalesced_when_identical
    record(rules_evaluated: 1, notes: ['Foo (#1): no issues matched'])
    record(rules_evaluated: 1, notes: ['Foo (#1): no issues matched'])
    assert_equal 1, AutomationRulesRun.count
    assert_equal 2, AutomationRulesRun.first.runs_count
    assert_not AutomationRulesRun.first.noop?
    assert AutomationRulesRun.first.uneventful?

    record(rules_evaluated: 2, notes: ['Foo (#1): no issues matched', 'Bar (#2): no issues matched'])
    assert_equal 2, AutomationRulesRun.count
  end

  def test_noop_runs_are_not_coalesced_across_sources_or_after_activity
    record(source: 'web')
    record(source: 'rake')
    assert_equal 2, AutomationRulesRun.count
    record(source: 'rake', rules_evaluated: 1, issues_matched: 1, actions_applied: 1)
    record(source: 'rake')
    assert_equal 4, AutomationRulesRun.count
  end

  def test_runs_with_errors_are_never_coalesced
    record(errors: ['x'])
    record(errors: ['x'])
    assert_equal 2, AutomationRulesRun.count
  end

  def test_keeps_only_last_runs
    t = Time.current
    (AutomationRulesRun::KEEP + 5).times { |i| record(rules_evaluated: 1, actions_applied: 1, at: t + i.minutes) }
    assert_equal AutomationRulesRun::KEEP, AutomationRulesRun.count
    assert_equal t.change(usec: 0) + 54.minutes, AutomationRulesRun.recent.first.started_at.change(usec: 0)
    assert_equal t.change(usec: 0) + 5.minutes, AutomationRulesRun.recent.last.started_at.change(usec: 0)
  end

  def test_checker_records_run_with_source
    EnabledModule.create!(project_id: 1, name: 'automation_rules')
    AutomationRule.create!(project_id: 1, author_id: 2, name: 'Due rule', trigger_type: 'scheduled',
                           trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                           actions: [{ 'type' => 'set_priority', 'value' => '6' }], next_run_at: 1.minute.ago)

    assert_equal 1, AutomationRulesChecker.check!(source: 'manual')
    run = AutomationRulesRun.recent.first
    assert_equal 'manual', run.source
    assert_equal 1, run.rules_evaluated
    assert_equal Issue.open.where(project_id: 1).count, run.issues_matched
    assert_equal run.issues_matched, run.actions_applied
  end

  def test_checker_defaults_to_rake_source_and_records_noop
    assert_equal 0, AutomationRulesChecker.check!
    run = AutomationRulesRun.recent.first
    assert_equal 'rake', run.source
    assert run.noop?
  end
end
