require "#{File.dirname(__FILE__)}/../test_helper"

# The scheduled rules checker: which rules run, what they do to their issues,
# how the schedule advances and how overlapping triggers (cron, web scheduler,
# check URL, "Run checker now") are kept from consuming one occurrence twice.
class AutomationRulesCheckerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues, :journals, :journal_details, :workflows

  # before_lock runs right before the row lock the checker takes on a rule,
  # standing in for another trigger that gets to the rule first.
  cattr_accessor :before_lock
  AutomationRule.prepend(Module.new do
    def with_lock(*args, &)
      AutomationRulesCheckerTest.before_lock&.call(self)
      super
    end
  end)

  def setup
    AutomationRule.delete_all
    AutomationRulesRun.delete_all
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'automation_rules')
    @author = User.find(2)
    User.current = nil
  end

  def teardown
    self.class.before_lock = nil
    User.current = nil
  end

  # A due "every hour" rule setting priority High (6) on New (1) issues of ecookbook.
  def create_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: @author, name: 'Hourly rule',
                             trigger_type: 'scheduled', note_marker: false,
                             trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' },
                             conditions: [{ 'type' => 'status', 'operator' => 'is', 'value' => '1' }],
                             actions: [{ 'type' => 'set_priority', 'value' => '6' }],
                             next_run_at: 1.minute.ago }.merge(attributes))
  end

  def new_issues
    Issue.where(project_id: @project.id, status_id: 1).order(:id)
  end

  def priorities
    new_issues.pluck(:id, :priority_id)
  end

  def test_due_rule_applies_its_actions_to_the_matching_issues_and_advances
    rule = create_rule
    targets = new_issues.to_a
    assert_not_empty targets
    others = Issue.where.not(id: targets.map(&:id)).pluck(:id, :priority_id)

    assert_equal 1, AutomationRulesChecker.check!

    targets.each { |issue| assert_equal 6, issue.reload.priority_id, "issue ##{issue.id}" }
    assert_equal others, Issue.where.not(id: targets.map(&:id)).pluck(:id, :priority_id)
    rule.reload
    assert rule.next_run_at > Time.current
    assert_in_delta Time.current + 1.hour, rule.next_run_at, 5
    assert_in_delta Time.current, rule.last_run_at, 5
    assert_equal targets.size, rule.runs_count
    assert_nil rule.last_error

    run = AutomationRulesRun.recent.first
    assert_equal 'rake', run.source
    assert_equal 1, run.rules_evaluated
    assert_equal targets.size, run.issues_matched
    assert_equal targets.size, run.actions_applied
    assert_nil run.error_messages
    assert_match(/Hourly rule \(##{rule.id}\): #{targets.size} issues matched/, run.notes)
  end

  def test_running_the_checker_twice_does_not_run_the_rule_again
    rule = create_rule
    assert_equal 1, AutomationRulesChecker.check!
    assert_equal 0, AutomationRulesChecker.check!
    assert_equal new_issues.count, rule.reload.runs_count
  end

  def test_rules_not_due_inactive_or_event_based_are_ignored
    create_rule(name: 'Later', next_run_at: 1.hour.from_now)
    create_rule(name: 'Off', active: false)
    AutomationRule.create!(project: @project, author: @author, name: 'Event', trigger_type: 'issue_updated',
                           actions: [{ 'type' => 'set_priority', 'value' => '6' }])
    before = priorities
    assert_equal 0, AutomationRulesChecker.check!
    assert_equal before, priorities
    assert AutomationRulesRun.recent.first.noop?
  end

  def test_missed_occurrences_are_coalesced_into_one_run
    rule = create_rule(next_run_at: 10.hours.ago)
    assert_equal 1, AutomationRulesChecker.check!
    assert_in_delta Time.current + 1.hour, rule.reload.next_run_at, 5
    assert_equal 0, AutomationRulesChecker.check!
  end

  def test_time_of_day_rule_moves_to_the_next_occurrence
    rule = create_rule(trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day',
                                          'time_of_day' => '09:00' },
                       next_run_at: 1.minute.ago)
    assert_equal 1, AutomationRulesChecker.check!
    next_run = rule.reload.next_run_at.in_time_zone(@author.time_zone || Time.zone)
    assert next_run > Time.current
    assert next_run <= 1.day.from_now
    assert_equal [9, 0], [next_run.hour, next_run.min]
  end

  def test_global_rule_covers_every_project
    rule = create_rule(project: nil, author: User.find(1))
    assert_equal 1, AutomationRulesChecker.check!
    assert_equal [6], Issue.where(status_id: 1).pluck(:priority_id).uniq
    assert_nil rule.reload.last_error
  end

  def test_subprojects_are_covered_only_when_the_rule_says_so
    sub = Project.find(3) # subproject of ecookbook
    EnabledModule.create!(project: sub, name: 'automation_rules')
    sub_issue = Issue.create!(project: sub, tracker_id: 1, author: @author, subject: 'Sub', status_id: 1,
                              priority_id: 5)

    create_rule(apply_to_subprojects: false)
    AutomationRulesChecker.check!
    assert_equal 5, sub_issue.reload.priority_id

    create_rule(name: 'Inherited', apply_to_subprojects: true)
    AutomationRulesChecker.check!
    assert_equal 6, sub_issue.reload.priority_id
  end

  def test_rule_of_a_project_with_the_module_disabled_is_skipped_with_a_note
    EnabledModule.where(project_id: @project.id, name: 'automation_rules').delete_all
    rule = create_rule
    before = priorities
    assert_equal 1, AutomationRulesChecker.check!
    assert_equal before, priorities
    assert rule.reload.next_run_at > Time.current
    run = AutomationRulesRun.recent.first
    assert_equal 0, run.rules_evaluated
    assert_match(/module is disabled on project eCookbook/, run.notes)
  end

  def test_actions_run_as_the_rule_author_and_are_journaled
    create_rule(actions: [{ 'type' => 'add_note', 'text' => 'stale {{issue.id}}' }], note_marker: true)
    issue = new_issues.first
    before = issue.journals.count
    AutomationRulesChecker.check!
    journal = issue.journals.order(:id).last
    assert_equal before + 1, issue.journals.count
    assert_equal @author, journal.user
    assert_match(/stale #{issue.id}/, journal.notes)
    assert_match(/automation rule: Hourly rule/, journal.notes)
  end

  def test_an_action_refused_by_redmine_is_recorded_and_does_not_stop_the_others
    bad = create_rule(name: 'Bad', actions: [{ 'type' => 'set_priority', 'value' => '9999' }])
    good = create_rule(name: 'Good')

    assert_equal 2, AutomationRulesChecker.check!

    assert_equal [6], new_issues.pluck(:priority_id).uniq
    assert_not_nil bad.reload.last_error
    assert_nil good.reload.last_error
    assert bad.next_run_at > Time.current
    run = AutomationRulesRun.recent.first
    assert_equal 2, run.rules_evaluated
    assert_match(/Bad \(##{bad.id}\): ##{new_issues.first.id}: /, run.error_messages)
  end

  def test_an_unexpected_failure_rolls_the_occurrence_back_and_keeps_the_error
    rule = create_rule
    next_run = rule.next_run_at
    before = priorities
    AutomationRule.any_instance.stubs(:finish_scheduled_run!).raises(ActiveRecord::StatementInvalid, 'lost connection')

    assert_equal 1, AutomationRulesChecker.check!

    assert_equal before, priorities
    rule.reload
    assert_equal next_run.to_i, rule.next_run_at.to_i
    assert_match(/lost connection/, rule.last_error)
    assert_match(/Hourly rule \(##{rule.id}\): ActiveRecord::StatementInvalid: lost connection/,
                 AutomationRulesRun.recent.first.error_messages)
  end

  def test_a_failing_rule_does_not_stop_the_other_due_rules
    failing = create_rule(name: 'Failing')
    other = create_rule(name: 'Other', actions: [{ 'type' => 'set_done_ratio', 'value' => '50' }])
    self.class.before_lock = ->(locked) { raise 'boom' if locked.id == failing.id }
    before = priorities

    assert_equal 2, AutomationRulesChecker.check!

    assert_equal before, priorities
    assert_equal [50], new_issues.pluck(:done_ratio).uniq
    assert_match(/boom/, failing.reload.last_error)
    assert other.reload.next_run_at > Time.current
  end

  def test_a_rule_another_trigger_just_ran_is_not_run_again
    rule = create_rule
    self.class.before_lock = lambda do |locked|
      AutomationRule.where(id: locked.id).update_all(next_run_at: 30.minutes.from_now)
    end
    before = priorities

    assert_equal 1, AutomationRulesChecker.check!

    assert_equal before, priorities
    assert_equal 0, rule.reload.runs_count
    assert_equal 0, AutomationRulesRun.recent.first.rules_evaluated
  end

  def test_a_rule_deleted_before_it_runs_is_skipped
    rule = create_rule
    self.class.before_lock = ->(locked) { AutomationRule.where(id: locked.id).delete_all }
    assert_equal 1, AutomationRulesChecker.check!
    assert_nil AutomationRulesRun.recent.first.error_messages
    assert_not AutomationRule.exists?(rule.id)
  end

  def test_scheduled_trigger_is_passed_to_the_conditions
    seen = []
    RedmineAutomationRules::Conditions::Status.any_instance.stubs(:matches?).with do |_issue, context|
      seen << context[:trigger]
      true
    end.returns(false)
    create_rule
    AutomationRulesChecker.check!
    assert_equal ['scheduled'], seen.uniq
  end
end
