require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesExecutionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues, :journals, :journal_details, :workflows

  def setup
    @project = Project.find(1)
    @author = User.find(2)
    @issue = Issue.find(1)
    User.current = nil
  end

  def teardown
    User.current = nil
  end

  def build_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: @author, name: 'Logged rule',
                             trigger_type: 'issue_updated' }.merge(attributes))
  end

  def run_rule(rule, issue = @issue, **)
    RedmineAutomationRules::Runner.new(rule, issue, **).run
  end

  def test_matching_run_creates_an_execution_with_the_applied_actions
    rule = build_rule(actions: [{ 'type' => 'set_priority', 'value' => '6' }, { 'type' => 'add_note', 'text' => 'Hi' }])
    assert_difference 'AutomationRulesExecution.count' do
      run_rule(rule, trigger: 'issue_updated')
    end
    execution = rule.executions.recent.first
    assert_equal @issue, execution.issue
    assert_equal 'issue_updated', execution.trigger
    assert_equal I18n.t(:automation_rules_trigger_issue_updated), execution.trigger_label
    assert_equal ['set priority to High', 'add note "Hi"'], execution.applied_list
    assert execution.success?
    assert_nil execution.error
    assert_equal 1, rule.reload.runs_count
  end

  def test_failed_run_records_the_error
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '99' }])
    run_rule(rule)
    execution = rule.executions.recent.first
    assert_not execution.success?
    assert_match(/status/i, execution.error)
    assert_equal rule.reload.last_error, execution.error
  end

  def test_non_matching_and_dry_runs_are_not_logged
    rule = build_rule(conditions: [{ 'type' => 'status', 'operator' => 'is_closed' }],
                      actions: [{ 'type' => 'add_note', 'text' => 'Hi' }])
    assert_no_difference 'AutomationRulesExecution.count' do
      run_rule(rule)
    end

    rule = build_rule(actions: [{ 'type' => 'add_note', 'text' => 'Hi' }])
    assert_no_difference 'AutomationRulesExecution.count' do
      result = run_rule(rule, dry_run: true)
      assert result.matched?
    end
    assert_nil rule.reload.last_run_at
  end

  def test_manual_and_test_triggers_have_their_own_labels
    rule = build_rule
    execution = AutomationRulesExecution.create!(automation_rule: rule, issue: @issue, trigger: 'manual',
                                                 created_at: Time.current)
    assert_equal I18n.t(:automation_rules_execution_trigger_manual), execution.trigger_label
    execution.trigger = 'whatever'
    assert_equal 'whatever', execution.trigger_label
  end

  def test_only_the_last_200_executions_per_rule_are_kept
    rule = build_rule
    other = build_rule(name: 'Other')
    now = Time.current
    rows = (1..(AutomationRulesExecution::KEEP + 5)).map do |i|
      { automation_rule_id: rule.id, issue_id: @issue.id, trigger: 'issue_updated', applied: "action #{i}",
        created_at: now }
    end
    AutomationRulesExecution.insert_all(rows)
    AutomationRulesExecution.create!(automation_rule: other, issue: @issue, trigger: 'issue_updated', created_at: now)

    result = run_rule(rule.reload)
    assert result.matched?

    assert_equal AutomationRulesExecution::KEEP, rule.executions.count
    assert_equal 1, other.executions.count
    kept = rule.executions.recent.pluck(:applied)
    assert_nil kept.last.match(/action [1-5]$/), 'the oldest rows should have been pruned'
    assert_equal "action #{AutomationRulesExecution::KEEP + 5}", kept[1]
  end

  def test_executions_are_deleted_with_the_rule
    rule = build_rule(actions: [{ 'type' => 'add_note', 'text' => 'Hi' }])
    run_rule(rule)
    assert_difference 'AutomationRulesExecution.count', -1 do
      rule.destroy
    end
  end

  def test_rules_fired_on_lists_each_rule_once_newest_first
    first = build_rule(name: 'First', actions: [{ 'type' => 'add_note', 'text' => 'One' }])
    second = build_rule(name: 'Second', actions: [{ 'type' => 'add_note', 'text' => 'Two' }])
    run_rule(first)
    run_rule(second)
    run_rule(first)
    run_rule(first, Issue.find(2))

    executions = AutomationRulesExecution.rules_fired_on(@issue)
    assert_equal [first, second], executions.map(&:automation_rule)
    assert_equal 'add note "One"', executions.first.applied
  end

  def test_logging_failures_do_not_break_the_run
    rule = build_rule(actions: [{ 'type' => 'add_note', 'text' => 'Hi' }])
    broken = Module.new do
      def record!(_result)
        raise 'db down'
      end
    end
    AutomationRulesExecution.singleton_class.prepend(broken)
    begin
      result = run_rule(rule)
      assert result.matched?
      assert result.success?
    ensure
      broken.send(:remove_method, :record!)
    end
    assert_equal 1, rule.reload.runs_count
  end
end
