require "#{File.dirname(__FILE__)}/../test_helper"

class WebSchedulerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  WebScheduler = RedmineAutomationRules::WebScheduler

  def setup
    AutomationRule.delete_all
    AutomationRulesSchedulerLock.delete_all
    WebScheduler.reset!
    WebScheduler.synchronous = true
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'web', 'web_check_interval' => 5 }
    EnabledModule.create!(project_id: 1, name: 'automation_rules')
    @rule = AutomationRule.create!(project_id: 1, author_id: 2, name: 'Due rule', trigger_type: 'scheduled',
                                   trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                                   actions: [{ 'type' => 'set_priority', 'value' => '6' }], next_run_at: 1.minute.ago)
  end

  def teardown
    WebScheduler.synchronous = false
    WebScheduler.reset!
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
  end

  def test_does_nothing_in_cron_mode
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
    assert_equal false, WebScheduler.maybe_run!
    assert_equal 0, @rule.reload.runs_count
  end

  def test_unknown_mode_falls_back_to_cron
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'bogus' }
    assert_equal 'cron', WebScheduler.mode
    assert_not WebScheduler.enabled?
  end

  def test_runs_due_rules_once_per_interval
    assert_equal true, WebScheduler.maybe_run!
    assert @rule.reload.runs_count.positive?
    assert @rule.next_run_at > Time.current
    assert_equal 'web', AutomationRulesRun.recent.first.source

    # second call within the interval is a no-op (per-process throttle)
    assert_equal false, WebScheduler.maybe_run!

    # another process (throttle reset) still loses the DB lock
    WebScheduler.reset!
    assert_equal false, WebScheduler.maybe_run!
  end

  def test_runs_again_after_interval_elapsed
    assert_equal true, WebScheduler.maybe_run!
    runs = @rule.reload.runs_count
    travel 6.minutes do
      AutomationRule.update_all(next_run_at: 1.minute.ago)
      WebScheduler.reset!
      assert_equal true, WebScheduler.maybe_run!
    end
    assert_equal runs * 2, @rule.reload.runs_count
  end

  def test_lock_claim_is_exclusive
    assert AutomationRulesSchedulerLock.claim?(5.minutes)
    assert_not AutomationRulesSchedulerLock.claim?(5.minutes)
    assert AutomationRulesSchedulerLock.claim?(5.minutes, 6.minutes.from_now)
  end

  def test_interval_defaults_when_setting_is_invalid
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'web', 'web_check_interval' => '0' }
    assert_equal 5.minutes, WebScheduler.interval
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'web', 'web_check_interval' => '30' }
    assert_equal 30.minutes, WebScheduler.interval
  end

  def test_checker_failure_is_logged_not_raised
    AutomationRulesChecker.stubs(:check!).raises(RuntimeError, 'boom')
    assert_equal false, WebScheduler.maybe_run!
  end
end
