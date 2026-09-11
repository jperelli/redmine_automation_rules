require "#{File.dirname(__FILE__)}/../test_helper"

# The "Automation" block the view hook adds to the issue sidebar.
class IssueSidebarHookTest < ActionController::TestCase
  tests IssuesController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :journals, :journal_details, :workflows,
           :custom_fields, :custom_fields_projects, :custom_fields_trackers, :custom_values, :queries

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['automation_rules']
    Role.find(1).add_permission!(:view_automation_rules)
    @issue = Issue.find(1)
    @rule = AutomationRule.create!(project: @project, author: User.find(2), name: 'Sidebar rule',
                                   trigger_type: 'issue_updated', actions: [{ 'type' => 'add_note', 'text' => 'Hi' }])
    @request.session[:user_id] = 2
  end

  def test_issue_without_executions_shows_no_block
    get :show, params: { id: @issue.id }
    assert_response :success
    assert_select 'ul.automation-rules-sidebar', count: 0
  end

  def test_issue_lists_the_rules_that_ran_on_it
    other = AutomationRule.create!(project: @project, author: User.find(2), name: 'Other rule',
                                   trigger_type: 'issue_created', actions: [{ 'type' => 'add_note', 'text' => 'Yo' }])
    [2.hours.ago, 1.hour.ago].each do |at|
      AutomationRulesExecution.create!(automation_rule: @rule, issue: @issue, trigger: 'issue_updated',
                                       applied: 'add note "Hi"', created_at: at)
    end
    AutomationRulesExecution.create!(automation_rule: other, issue: @issue, trigger: 'issue_created', error: 'boom',
                                     created_at: Time.current)
    AutomationRulesExecution.create!(automation_rule: other, issue: Issue.find(2), trigger: 'issue_created',
                                     created_at: Time.current)

    get :show, params: { id: @issue.id }
    assert_response :success
    assert_select '#sidebar h3', text: I18n.t(:automation_rules_sidebar_title)
    assert_select 'ul.automation-rules-sidebar li', count: 2
    assert_select 'ul.automation-rules-sidebar li.automation-rule-execution-error a[href=?]',
                  "/projects/ecookbook/automation_rules/#{other.id}", text: 'Other rule'
    assert_select 'ul.automation-rules-sidebar li.automation-rule-execution-ok[title=?] a', 'add note "Hi"',
                  text: 'Sidebar rule'
  end

  def test_block_is_hidden_without_permission_or_module
    AutomationRulesExecution.create!(automation_rule: @rule, issue: @issue, trigger: 'issue_updated',
                                     created_at: Time.current)

    Role.find(1).remove_permission!(:view_automation_rules)
    Role.find(1).remove_permission!(:manage_automation_rules)
    get :show, params: { id: @issue.id }
    assert_response :success
    assert_select 'ul.automation-rules-sidebar', count: 0

    Role.find(1).add_permission!(:manage_automation_rules)
    get :show, params: { id: @issue.id }
    assert_select 'ul.automation-rules-sidebar li', count: 1

    @project.enabled_module_names = @project.enabled_module_names - ['automation_rules']
    get :show, params: { id: @issue.id }
    assert_response :success
    assert_select 'ul.automation-rules-sidebar', count: 0
  end

  def test_global_rules_link_to_the_admin_page_and_are_admin_only
    global = AutomationRule.create!(project: nil, author: User.find(1), name: 'Global rule',
                                    trigger_type: 'issue_updated')
    AutomationRulesExecution.create!(automation_rule: global, issue: @issue, trigger: 'issue_updated',
                                     created_at: Time.current)

    get :show, params: { id: @issue.id }
    assert_select 'ul.automation-rules-sidebar', count: 0

    @request.session[:user_id] = 1
    get :show, params: { id: @issue.id }
    assert_select 'ul.automation-rules-sidebar li a[href=?]', "/automation_rules/#{global.id}", text: 'Global rule'
  end
end
