require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesAdminControllerTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations

  teardown do
    User.current = nil
  end

  def test_index_requires_admin
    log_user('jsmith', 'jsmith')
    get '/admin/automation_rules'
    assert_response :forbidden
  end

  def test_index_renders_for_admin
    log_user('admin', 'admin')
    get '/admin/automation_rules'
    assert_response :success
    assert_select 'h2', text: I18n.t(:label_automation_rules)
  end

  def test_admin_menu_has_entry
    log_user('admin', 'admin')
    get '/admin'
    assert_response :success
    assert_select '#admin-menu a.automation-rules', text: I18n.t(:label_automation_rules)
  end
end
