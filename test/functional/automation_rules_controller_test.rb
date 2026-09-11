require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['automation_rules']
    Role.find(1).add_permission!(:manage_automation_rules)
    @request.session[:user_id] = 2
  end

  def test_index
    get :index, params: { project_id: @project.id }
    assert_response :success
    assert_select 'h2', text: I18n.t(:label_automation_rules)
  end

  def test_index_requires_permission
    Role.find(1).remove_permission!(:manage_automation_rules)
    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  def test_index_requires_module
    @project.enabled_module_names = @project.enabled_module_names - ['automation_rules']
    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  def test_project_menu_shows_automation_tab
    get :index, params: { project_id: @project.id }
    assert_select '#main-menu a.automation-rules', text: I18n.t(:label_automation_rules_menu)
  end
end
