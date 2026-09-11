require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesSysControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  def setup
    AutomationRule.delete_all
    Setting.sys_api_enabled = '1'
    Setting.sys_api_key = 'secret-key'
    EnabledModule.create!(project_id: 1, name: 'automation_rules')
    @rule = AutomationRule.create!(project_id: 1, author_id: 2, name: 'Due rule', trigger_type: 'scheduled',
                                   trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                                   actions: [{ 'type' => 'set_priority', 'value' => '6' }], next_run_at: 1.minute.ago)
  end

  def teardown
    Setting.sys_api_enabled = '0'
  end

  def test_check_runs_due_rules_with_valid_key
    get :check, params: { key: 'secret-key' }
    assert_response :success
    assert_match(/1 rule\(s\) run/, @response.body)
    assert @rule.reload.runs_count.positive?
    assert_equal 'endpoint', AutomationRulesRun.recent.first.source
  end

  def test_check_accepts_post
    post :check, params: { key: 'secret-key' }
    assert_response :success
  end

  def test_check_denied_with_wrong_key
    get :check, params: { key: 'wrong' }
    assert_response :forbidden
    assert_equal 0, @rule.reload.runs_count
  end

  def test_check_denied_when_sys_api_disabled
    Setting.sys_api_enabled = '0'
    get :check, params: { key: 'secret-key' }
    assert_response :forbidden
  end

  def test_check_route
    assert_routing({ method: 'get', path: '/automation_rules/check' },
                   { controller: 'automation_rules_sys', action: 'check' })
    assert_routing({ method: 'post', path: '/automation_rules/check' },
                   { controller: 'automation_rules_sys', action: 'check' })
  end
end
