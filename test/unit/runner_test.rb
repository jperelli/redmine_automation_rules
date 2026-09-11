require "#{File.dirname(__FILE__)}/../test_helper"

class RunnerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues, :journals, :journal_details, :workflows

  def setup
    @project = Project.find(1)
    @author = User.find(2) # Manager on ecookbook
    @issue = Issue.find(1) # Bug, status New, project 1
    User.current = nil
  end

  def teardown
    User.current = nil
  end

  def build_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: @author, name: 'Runner rule',
                             trigger_type: 'issue_updated' }.merge(attributes))
  end

  def run_rule(rule, issue = @issue, **)
    RedmineAutomationRules::Runner.new(rule, issue, **).run
  end

  def test_conditions_are_evaluated_and_reported
    rule = build_rule(conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' },
                                   { 'type' => 'status', 'operator' => 'is_closed' }])
    result = run_rule(rule)
    assert_not result.matched?
    assert_equal([true, false], result.conditions.map { |c| c[:matched] })
    assert_equal(['tracker is Bug', 'status is closed'], result.conditions.map { |c| c[:description] })
    assert_empty result.applied
    assert_nil rule.reload.last_run_at
  end

  def test_matching_rule_applies_actions_and_records_the_run
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '2' },
                                { 'type' => 'add_note', 'text' => 'Moved {{issue.id}} by {{rule.name}}' }])
    result = run_rule(rule)
    assert result.success?, result.error
    assert result.matched?
    assert_equal ['set status to Assigned', 'add note "Moved {{issue.id}} by {{rule.name}}"'], result.applied
    assert_equal({ 'status_id' => [1, 2] }, result.changes.slice('status_id'))

    @issue.reload
    assert_equal 2, @issue.status_id
    journal = @issue.journals.last
    assert_equal @author, journal.user
    assert_equal "Moved 1 by Runner rule\n\n_(automation rule: Runner rule)_", journal.notes
    assert_equal 1, rule.reload.runs_count
    assert_not_nil rule.last_run_at
    assert_nil rule.last_error
  end

  def test_note_marker_can_be_disabled
    rule = build_rule(note_marker: false, actions: [{ 'type' => 'add_note', 'text' => 'Plain' }])
    run_rule(rule)
    assert_equal 'Plain', @issue.reload.journals.last.notes
  end

  def test_actions_run_as_the_rule_author
    User.current = User.find(1)
    rule = build_rule(actions: [{ 'type' => 'add_note', 'text' => 'by {{user}}' }])
    run_rule(rule)
    assert_equal User.find(1), User.current
    assert_match(/^by John Smith/, @issue.reload.journals.last.notes)
  end

  def test_dry_run_does_not_save_anything
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '2' }, { 'type' => 'add_note', 'text' => 'Dry' }])
    journals_before = Journal.count
    result = run_rule(rule, dry_run: true)
    assert result.matched?
    assert result.success?, result.error
    assert_equal [1, 2], result.changes['status_id']
    assert_match(/^Dry/, result.notes)

    assert_equal 1, @issue.reload.status_id
    assert_equal journals_before, Journal.count
    assert_equal 0, rule.reload.runs_count
    assert_nil rule.last_run_at
  end

  def test_workflow_refusal_is_recorded_not_raised
    # Developer role (user 3) has a limited workflow; a New -> Closed transition is refused.
    developer = User.find(3)
    WorkflowTransition.where(role_id: 2, tracker_id: 1).delete_all
    rule = build_rule(author: developer, actions: [{ 'type' => 'set_status', 'value' => '5' }])
    result = run_rule(rule)
    assert result.matched?
    assert_not result.success?
    assert_match(/does not allow/, result.error)
    assert_equal 1, @issue.reload.status_id
    assert_match(/does not allow/, rule.reload.last_error)
    assert_equal 0, rule.runs_count
  end

  def test_validation_errors_are_recorded_not_raised
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '999' }])
    result = run_rule(rule)
    assert_not result.success?
    assert_match(/status #999 not found/, result.error)
    assert_equal 1, @issue.reload.status_id
  end

  def test_no_op_actions_do_not_create_a_journal
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '1' }])
    journals_before = Journal.count
    result = run_rule(rule)
    assert result.success?, result.error
    assert_equal journals_before, Journal.count
    assert_equal 1, rule.reload.runs_count
  end
end
