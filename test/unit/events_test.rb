require "#{File.dirname(__FILE__)}/../test_helper"

# Event triggers: Issue / TimeEntry saves firing rules through Events, the
# "restrict to" sub-options of "issue updated" and the loop guard.
class EventsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues, :journals, :journal_details, :workflows,
           :custom_fields, :custom_fields_projects, :custom_fields_trackers, :custom_values

  Events = RedmineAutomationRules::Events

  def setup
    @project = Project.find(1)
    @author = User.find(2) # Manager on ecookbook
    EnabledModule.create!(project: @project, name: 'automation_rules')
    @issue = Issue.find(1) # Bug, New, ecookbook
    @existing_journal_ids = Journal.pluck(:id)
    User.current = @author
    Events.synchronous = true
  end

  def teardown
    User.current = nil
    Events.synchronous = nil
  end

  def build_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: @author, name: 'Event rule',
                             trigger_type: 'issue_updated', note_marker: false,
                             actions: [{ 'type' => 'add_note', 'text' => 'fired {{rule.name}}' }] }.merge(attributes))
  end

  # Reloads first: rules act on their own copy of the issue, so the copy that
  # fired the callback is stale afterwards (like a request's instance would be).
  def update_issue(issue = @issue, notes: nil, **attributes)
    issue.reload
    issue.clear_journal
    issue.init_journal(User.current, notes) if notes || attributes.any?
    issue.attributes = attributes
    assert issue.save, issue.errors.full_messages.to_sentence
    issue
  end

  def new_issue(attributes = {})
    Issue.create!({ project: @project, tracker_id: 1, author: @author, subject: 'Event issue',
                    status_id: 1, priority_id: 5 }.merge(attributes))
  end

  def with_logger(logger)
    previous = Rails.logger
    Rails.logger = logger
    yield
  ensure
    Rails.logger = previous
  end

  def notes_on(issue)
    issue.journals.where.not(id: @existing_journal_ids).order(:id).map(&:notes).compact_blank
  end

  # --- which trigger fires ---------------------------------------------------------

  def test_issue_created_fires_created_rules_then_updated_rules_for_their_changes
    created = build_rule(trigger_type: 'issue_created', name: 'created')
    updated = build_rule(trigger_type: 'issue_updated', name: 'updated')

    issue = new_issue
    assert_equal ['fired created', 'fired updated'], notes_on(issue)
    assert_equal 1, created.reload.runs_count
    assert_equal 1, updated.reload.runs_count
  end

  def test_issue_created_alone_does_not_fire_updated_rules
    updated = build_rule(trigger_type: 'issue_updated', name: 'updated')
    issue = new_issue
    assert_empty notes_on(issue)
    assert_equal 0, updated.reload.runs_count
  end

  def test_issue_updated_fires_on_any_change_but_not_on_create
    rule = build_rule(name: 'updated')
    new_issue
    update_issue(subject: 'Changed')
    assert_equal ['fired updated'], notes_on(@issue)
    assert_equal 1, rule.reload.runs_count
  end

  def test_a_save_that_changes_nothing_fires_nothing
    rule = build_rule
    @issue.save!
    assert_empty notes_on(@issue)
    assert_equal 0, rule.reload.runs_count
  end

  def test_issue_closed_and_reopened
    closed = build_rule(trigger_type: 'issue_closed', name: 'closed')
    reopened = build_rule(trigger_type: 'issue_reopened', name: 'reopened')

    update_issue(status_id: 2) # Assigned: still open
    assert_empty notes_on(@issue)

    update_issue(status_id: 5) # Closed
    assert_equal ['fired closed'], notes_on(@issue)

    update_issue(status_id: 6) # Rejected: closed -> closed
    assert_equal ['fired closed'], notes_on(@issue)

    update_issue(status_id: 1)
    assert_equal ['fired closed', 'fired reopened'], notes_on(@issue)
    assert_equal 1, closed.reload.runs_count
    assert_equal 1, reopened.reload.runs_count
  end

  def test_closing_also_fires_issue_updated_rules
    build_rule(trigger_type: 'issue_updated', name: 'updated')
    build_rule(trigger_type: 'issue_closed', name: 'closed')
    update_issue(status_id: 5)
    assert_equal ['fired updated', 'fired closed'], notes_on(@issue)
  end

  def test_time_entry_logged
    rule = build_rule(trigger_type: 'time_entry_logged', name: 'time',
                      actions: [{ 'type' => 'add_note', 'text' => 'logged on {{issue.id}}' }])
    TimeEntry.create!(project: @project, issue: @issue, user: @author, author: @author, hours: 1.5,
                      activity_id: 9, spent_on: Date.today)
    assert_equal ['logged on 1'], notes_on(@issue)
    assert_equal 1, rule.reload.runs_count

    TimeEntry.create!(project: @project, user: @author, author: @author, hours: 1, activity_id: 9, spent_on: Date.today)
    assert_equal 1, rule.reload.runs_count
  end

  def test_time_entry_context_is_available_to_conditions
    threshold = @issue.total_spent_hours + 5
    build_rule(trigger_type: 'time_entry_logged', name: 'budget',
               conditions: [{ 'type' => 'time_spent', 'operator' => 'gt_hours', 'value' => threshold.to_s }],
               actions: [{ 'type' => 'add_note', 'text' => 'over budget' }])
    TimeEntry.create!(project: @project, issue: @issue, user: @author, author: @author, hours: 2,
                      activity_id: 9, spent_on: Date.today)
    assert_empty notes_on(@issue)
    TimeEntry.create!(project: @project, issue: @issue, user: @author, author: @author, hours: 9,
                      activity_id: 9, spent_on: Date.today)
    assert_equal ['over budget'], notes_on(@issue)
  end

  # --- "restrict to" sub-options of issue updated ------------------------------------

  def test_restrict_to_field_changed
    build_rule(trigger_options: { 'change' => 'field', 'field' => 'priority_id' })
    update_issue(subject: 'Other field')
    assert_empty notes_on(@issue)
    update_issue(priority_id: 6)
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_restrict_to_custom_field_changed
    field = CustomField.find(2) # Searchable field, string, Bug tracker
    build_rule(trigger_options: { 'change' => 'field', 'field' => "cf_#{field.id}" })
    update_issue(subject: 'Other field')
    assert_empty notes_on(@issue)
    update_issue(custom_field_values: { field.id.to_s => 'new value' })
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_restrict_to_status_changed_to
    build_rule(trigger_options: { 'change' => 'status_to', 'status_id' => '3' })
    update_issue(status_id: 2)
    assert_empty notes_on(@issue)
    update_issue(status_id: 3)
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_restrict_to_assignee_changed
    build_rule(trigger_options: { 'change' => 'assignee' })
    update_issue(status_id: 2)
    assert_empty notes_on(@issue)
    update_issue(assigned_to_id: 3)
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_restrict_to_note_added
    build_rule(trigger_options: { 'change' => 'note' }, actions: [{ 'type' => 'set_priority', 'value' => '6' }])
    priority_before = @issue.priority_id
    update_issue(status_id: 2)
    assert_equal priority_before, @issue.reload.priority_id
    update_issue(notes: 'A comment')
    assert_equal 6, @issue.reload.priority_id
  end

  def test_restrict_to_done_ratio_reached_100
    build_rule(trigger_options: { 'change' => 'done_ratio_100' })
    update_issue(done_ratio: 50)
    assert_empty notes_on(@issue)
    update_issue(done_ratio: 100)
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_restrict_to_due_date_changed
    build_rule(trigger_options: { 'change' => 'due_date' })
    update_issue(start_date: Date.today)
    assert_empty notes_on(@issue)
    update_issue(due_date: Date.today + 3)
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  def test_matches_event_without_an_event_always_matches
    rule = build_rule(trigger_options: { 'change' => 'status_to', 'status_id' => '3' })
    assert rule.matches_event?({})
    assert build_rule(trigger_type: 'issue_closed').matches_event?(event: Events::IssueEvent.new(changes: {}))
  end

  # --- which rules are considered -------------------------------------------------

  def test_inactive_rules_and_other_projects_are_skipped
    build_rule(active: false, name: 'inactive')
    build_rule(project: Project.find(2), name: 'other project')
    update_issue(subject: 'Changed')
    assert_empty notes_on(@issue)
  end

  def test_rules_of_projects_without_the_module_are_skipped_but_global_rules_run
    EnabledModule.where(project_id: @project.id, name: 'automation_rules').delete_all
    build_rule(name: 'project rule')
    build_rule(project: nil, author: User.find(1), name: 'global rule')
    update_issue(subject: 'Changed')
    assert_equal ['fired global rule'], notes_on(@issue)
  end

  def test_subproject_inheritance
    subproject = Project.find(3) # child of ecookbook
    subissue = Issue.find(5)
    assert_equal subproject, subissue.project
    build_rule(name: 'inherited', apply_to_subprojects: true)
    build_rule(name: 'not inherited', apply_to_subprojects: false)
    update_issue(subissue, subject: 'Changed')
    assert_equal ['fired inherited'], notes_on(subissue)
  end

  def test_rules_run_in_order_global_first
    build_rule(name: 'second', position: 2)
    build_rule(name: 'first', position: 1)
    build_rule(name: 'global', project: nil, author: User.find(1))
    update_issue(subject: 'Changed')
    assert_equal ['fired global', 'fired first', 'fired second'], notes_on(@issue)
  end

  def test_conditions_are_evaluated_with_the_acting_user
    User.current = User.find(3) # dlopper
    build_rule(conditions: [{ 'type' => 'assignee', 'operator' => 'is_current_user' }])
    update_issue(subject: 'Changed')
    assert_empty notes_on(@issue)
    update_issue(assigned_to_id: 3)
    assert_equal ['fired Event rule'], notes_on(@issue)
    assert_equal @author, @issue.journals.last.user
  end

  def test_events_can_be_disabled
    build_rule
    Events.without_events { update_issue(subject: 'Silent') }
    assert_empty notes_on(@issue)
    update_issue(subject: 'Loud')
    assert_equal ['fired Event rule'], notes_on(@issue)
  end

  # --- failures -----------------------------------------------------------------

  def test_rule_errors_never_break_the_save
    rule = build_rule(actions: [{ 'type' => 'set_status', 'value' => '999' }])
    update_issue(subject: 'Changed')
    assert_equal 'Changed', @issue.reload.subject
    assert_match(/status #999 not found/, rule.reload.last_error)
  end

  def test_dispatch_failures_are_logged_not_raised
    build_rule
    AutomationRule.stubs(:active).raises(RuntimeError, 'boom')
    assert_nothing_raised { update_issue(subject: 'Changed') }
    assert_equal 'Changed', @issue.reload.subject
  end

  # --- loop guard -------------------------------------------------------------------

  def test_a_rule_fires_once_per_issue_per_chain
    rule = build_rule(actions: [{ 'type' => 'add_note', 'text' => 'once' }])
    update_issue(subject: 'Changed')
    assert_equal ['once'], notes_on(@issue)
    assert_equal 1, rule.reload.runs_count

    update_issue(subject: 'Changed again')
    assert_equal %w[once once], notes_on(@issue)
  end

  def test_a_rule_save_triggers_other_rules_but_not_itself_again
    build_rule(name: 'escalate', position: 1, trigger_options: { 'change' => 'field', 'field' => 'subject' },
               actions: [{ 'type' => 'set_priority', 'value' => '6' }])
    build_rule(name: 'on priority', position: 2, trigger_options: { 'change' => 'field', 'field' => 'priority_id' },
               actions: [{ 'type' => 'add_note', 'text' => 'priority is now {{issue.priority}}' }])
    update_issue(subject: 'Changed')
    @issue.reload
    assert_equal 6, @issue.priority_id
    assert_equal ['priority is now High'], notes_on(@issue)
    assert_equal 3, @issue.journals.where.not(id: @existing_journal_ids).count
  end

  def test_chains_stop_at_max_depth
    build_rule(trigger_type: 'issue_created', name: 'subtask factory',
               actions: [{ 'type' => 'create_issue', 'mode' => 'subtask', 'subject' => 'Child of {{issue.subject}}' }])
    log = StringIO.new
    with_logger(Logger.new(log)) { new_issue(subject: 'Root') }
    root = Issue.find_by(subject: 'Root')
    assert_equal Events::MAX_DEPTH, root.descendants.count
    assert_equal ['Child of Root', 'Child of Child of Root', 'Child of Child of Child of Root'],
                 root.descendants.order(:lft).map(&:subject)
    assert_includes log.string, "nested deeper than #{Events::MAX_DEPTH} levels"
    assert_nil Events.chain
  end

  def test_chain_state_is_cleared_after_a_failure
    build_rule(actions: [{ 'type' => 'set_status', 'value' => '999' }])
    update_issue(subject: 'Changed')
    assert_nil Events.chain
  end

  # --- async setting ---------------------------------------------------------------

  def test_async_setting_runs_inline_when_synchronous
    with_settings plugin_automation_rules: { 'run_actions_async' => '1' } do
      assert_not Events.async?
      build_rule
      update_issue(subject: 'Changed')
      assert_equal ['fired Event rule'], notes_on(@issue)
    end
  end

  def test_async_is_a_setting
    with_settings plugin_automation_rules: { 'run_actions_async' => '1' } do
      Events.synchronous = nil
      assert Events.async?
    end
    with_settings plugin_automation_rules: { 'run_actions_async' => '0' } do
      Events.synchronous = nil
      assert_not Events.async?
    end
  end

  # --- capture --------------------------------------------------------------------

  def test_capture_describes_the_save
    update_issue(status_id: 5, notes: 'Closing')
    event = Events.capture(@issue)
    assert_equal 1, event.issue_id
    assert_not event.created
    assert event.closing
    assert_not event.reopening
    assert_equal [1, 5], event.changes['status_id']
    assert event.changed?('status_id')
    assert_equal 5, event.new_value('status_id')
    assert_equal 1, event.old_value('status_id')
    assert_equal 'Closing', event.notes
    assert_equal @issue.journals.last, event.journal
    assert_equal %w[issue_updated issue_closed], event.triggers
  end
end
