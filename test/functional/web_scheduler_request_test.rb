require "#{File.dirname(__FILE__)}/../test_helper"

# Any Redmine controller request triggers the web scheduler when enabled.
class WebSchedulerRequestTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  def setup
    AutomationRule.delete_all
    AutomationRulesSchedulerLock.delete_all
    RedmineAutomationRules::WebScheduler.reset!
    RedmineAutomationRules::WebScheduler.synchronous = true
    EnabledModule.create!(project_id: 1, name: 'automation_rules')
    @rule = AutomationRule.create!(project_id: 1, author_id: 2, name: 'Due rule', trigger_type: 'scheduled',
                                   trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                                   actions: [{ 'type' => 'set_priority', 'value' => '6' }], next_run_at: 1.minute.ago)
  end

  def teardown
    RedmineAutomationRules::WebScheduler.synchronous = false
    RedmineAutomationRules::WebScheduler.reset!
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
  end

  def test_request_triggers_checker_in_web_mode
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'web', 'web_check_interval' => 5 }
    get '/'
    assert_response :success
    assert @rule.reload.runs_count.positive?
    assert_equal 'web', AutomationRulesRun.recent.first.source
  end

  def test_request_does_not_trigger_checker_in_cron_mode
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
    get '/'
    assert_response :success
    assert_equal 0, @rule.reload.runs_count
  end
end
