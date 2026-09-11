require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesSettingsTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  def setup
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
    RedmineAutomationRules::WebScheduler.reset!
    # A checker running in its own thread writes outside the test transaction,
    # so its rows would survive into the next test.
    RedmineAutomationRules::WebScheduler.synchronous = true
    log_user('admin', 'admin')
    AutomationRule.delete_all
    AutomationRulesRun.delete_all
  end

  def teardown
    RedmineAutomationRules::WebScheduler.synchronous = false
    RedmineAutomationRules::WebScheduler.reset!
    Setting.plugin_automation_rules = { 'scheduler_mode' => 'cron' }
  end

  def record(**attrs)
    defaults = { source: 'rake', started_at: 1.minute.ago, finished_at: Time.current,
                 rules_evaluated: 0, issues_matched: 0, actions_applied: 0, errors: [], notes: [] }
    AutomationRulesRun.record!(**defaults, **attrs)
  end

  def test_plugin_settings_page_renders
    get '/settings/plugin/automation_rules'
    assert_response :success
    assert_select 'input[name=?]', 'settings[run_actions_async]'
    assert_select 'select[name=?]', 'settings[scheduler_mode]' do
      assert_select 'option[value=cron][selected]'
      assert_select 'option[value=web]'
    end
    assert_select 'input[name=?][value="5"]', 'settings[web_check_interval]'
    assert_select 'code', text: %r{/automation_rules/check\?key=}
    assert_select 'a[href=?][data-method=post]', '/admin/automation_rules/run_checker'
    assert_select 'p.nodata'
  end

  def test_plugin_settings_page_lists_recent_runs
    record(source: 'endpoint', rules_evaluated: 1, errors: ['Auto close (#1): #7: Priority cannot be blank'])
    get '/settings/plugin/automation_rules'
    assert_response :success
    assert_select 'table.automation-rules-runs tbody tr.error', 1 do
      assert_select 'td', text: 'Check URL'
      assert_select 'td.error-messages', text: /Priority cannot be blank/
    end
  end

  def test_plugin_settings_page_lists_notes_not_as_errors
    record(rules_evaluated: 1, notes: ['Auto close (#1): no issues matched'])
    record(rules_evaluated: 1, notes: ['Auto close (#1): no issues matched'])
    get '/settings/plugin/automation_rules'
    assert_response :success
    assert_select 'table.automation-rules-runs tbody tr.error', 0
    assert_select 'table.automation-rules-runs tbody tr', 1 do
      assert_select 'td.notes', text: /no issues matched/
      assert_select 'td.error-messages', text: ''
      assert_select 'td span.info', text: /until/
    end
  end

  def test_plugin_settings_can_switch_to_web_mode
    post '/settings/plugin/automation_rules',
         params: { settings: { scheduler_mode: 'web', web_check_interval: '15', run_actions_async: '0' } }
    assert_redirected_to '/settings/plugin/automation_rules'
    assert_equal 'web', Setting.plugin_automation_rules['scheduler_mode']
    assert RedmineAutomationRules::WebScheduler.enabled?
    assert_equal 15.minutes, RedmineAutomationRules::WebScheduler.interval
  end

  def test_run_checker_now_runs_due_rules_and_redirects_to_settings
    EnabledModule.create!(project_id: 1, name: 'automation_rules')
    rule = AutomationRule.create!(project_id: 1, author_id: 2, name: 'Due rule', trigger_type: 'scheduled',
                                  trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                                  actions: [{ 'type' => 'set_priority', 'value' => '6' }], next_run_at: 1.minute.ago)
    post '/admin/automation_rules/run_checker'
    assert_redirected_to '/settings/plugin/automation_rules'
    assert rule.reload.runs_count.positive?
    run = AutomationRulesRun.recent.first
    assert_equal 'manual', run.source
    assert_equal 1, run.rules_evaluated

    follow_redirect!
    assert_select 'div.flash.notice', text: /1 scheduled rule\(s\) evaluated/
    assert_select 'table.automation-rules-runs tbody tr', 1
  end

  def test_run_checker_requires_admin
    reset!
    log_user('jsmith', 'jsmith')
    post '/admin/automation_rules/run_checker'
    assert_response :forbidden
  end
end
