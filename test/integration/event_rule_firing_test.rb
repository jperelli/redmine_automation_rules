require "#{File.dirname(__FILE__)}/../test_helper"

# End to end: issues created / updated through the web UI fire event rules.
class EventRuleFiringTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :journals, :journal_details, :workflows,
           :custom_fields, :custom_fields_projects, :custom_fields_trackers, :custom_values

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'automation_rules')
    RedmineAutomationRules::Events.synchronous = true
    log_user('jsmith', 'jsmith')
  end

  def teardown
    RedmineAutomationRules::Events.synchronous = nil
  end

  def test_issue_created_through_the_ui_fires_a_rule
    AutomationRule.create!(project: @project, author: User.find(2), name: 'Triage', trigger_type: 'issue_created',
                           conditions: [{ 'type' => 'assignee', 'operator' => 'is_nobody' }],
                           actions: [
                             { 'type' => 'set_assignee', 'mode' => 'author' },
                             { 'type' => 'add_note', 'text' => 'Assigned to {{issue.author}} by {{rule.name}}' }
                           ])

    assert_difference 'Issue.count' do
      post '/projects/ecookbook/issues',
           params: { issue: { tracker_id: 1, subject: 'Needs triage', priority_id: 5, status_id: 1 } }
    end
    issue = Issue.order(:id).last
    assert_redirected_to "/issues/#{issue.id}"
    assert_equal User.find(2), issue.assigned_to
    assert_equal ["Assigned to John Smith by Triage\n\n_(automation rule: Triage)_"], issue.journals.map(&:notes)

    follow_redirect!
    assert_response :success
    assert_select 'div.journal .wiki', text: /Assigned to John Smith by Triage/
  end

  def test_issue_closed_through_the_ui_fires_a_rule
    rule = AutomationRule.create!(project: @project, author: User.find(2), name: 'Done', trigger_type: 'issue_closed',
                                  note_marker: false,
                                  actions: [{ 'type' => 'set_done_ratio', 'value' => '100' }])
    issue = Issue.find(1)

    put "/issues/#{issue.id}", params: { issue: { status_id: 5 } }
    assert_redirected_to "/issues/#{issue.id}"

    issue.reload
    assert issue.closed?
    assert_equal 100, issue.done_ratio
    assert_equal 1, rule.reload.runs_count
    assert_nil rule.last_error
  end

  def test_rule_failure_does_not_break_the_request
    rule = AutomationRule.create!(project: @project, author: User.find(2), name: 'Broken',
                                  trigger_type: 'issue_updated',
                                  actions: [{ 'type' => 'set_status', 'value' => '999' }])

    put '/issues/1', params: { issue: { subject: 'Still saved' } }
    assert_redirected_to '/issues/1'
    assert_equal 'Still saved', Issue.find(1).subject
    assert_match(/999/, rule.reload.last_error)
  end
end
