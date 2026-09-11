require "#{File.dirname(__FILE__)}/../test_helper"

class ActionsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :groups_users,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issue_categories,
           :versions, :enumerations, :issues, :journals, :journal_details, :workflows, :watchers,
           :issue_relations, :custom_fields, :custom_fields_projects, :custom_fields_trackers, :custom_values

  Actions = RedmineAutomationRules::Actions

  def setup
    @project = Project.find(1)
    @author = User.find(2) # Manager on ecookbook
    @issue = Issue.find(1) # Bug, status New, project 1, unassigned
    @closed = Issue.find(8) # status Closed, project 1
    User.current = nil
    RedmineAutomationRules::Webhook.synchronous = true
    RedmineAutomationRules::Webhook.transport = nil
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    User.current = nil
    RedmineAutomationRules::Webhook.synchronous = nil
    RedmineAutomationRules::Webhook.transport = nil
  end

  def build_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: @author, name: 'Action rule', note_marker: false,
                             trigger_type: 'issue_updated' }.merge(attributes))
  end

  def run_actions(actions, issue = @issue, rule_attributes: {}, **)
    rule = build_rule(rule_attributes.merge(actions: actions))
    result = RedmineAutomationRules::Runner.new(rule, issue, **).run
    [result, rule]
  end

  def assert_applied(actions, issue = @issue, **)
    result, rule = run_actions(actions, issue, **)
    assert result.success?, result.error
    [result, rule]
  end

  def describe(row)
    Actions.build(row).describe
  end

  # -- registry -------------------------------------------------------------

  def test_all_requested_action_types_are_registered
    expected = %w[set_status set_assignee set_priority set_tracker set_category set_target_version set_due_date
                  set_start_date set_done_ratio set_custom_field add_watchers remove_watchers add_note set_private
                  close_issue reopen_issue create_issue send_email call_webhook update_parent]
    assert_equal expected.sort, Actions.registry.keys.sort
    Actions.all.each do |klass|
      assert_kind_of String, klass.label, klass.key
      assert Actions.schema.any? { |s| s['key'] == klass.key }, "#{klass.key} missing from schema"
    end
  end

  def test_each_action_type_validates_its_required_params
    Actions.all.each do |klass|
      action = klass.new('type' => klass.key)
      assert_kind_of Array, action.validate
      assert_kind_of String, action.describe, klass.key
    end
    assert_includes Actions.build('type' => 'call_webhook', 'url' => 'ftp://x').validate.join, 'http'
    assert_empty Actions.build('type' => 'call_webhook', 'url' => 'https://example.com/hook').validate
    assert_not_empty Actions.build('type' => 'set_assignee', 'mode' => 'user').validate
    assert_empty Actions.build('type' => 'set_assignee', 'mode' => 'author').validate
    assert_not_empty Actions.build('type' => 'update_parent', 'action' => 'set_status').validate
  end

  # -- simple attributes ----------------------------------------------------

  def test_set_priority
    assert_applied([{ 'type' => 'set_priority', 'value' => '6' }])
    assert_equal 6, @issue.reload.priority_id
    assert_equal 'set priority to High', describe('type' => 'set_priority', 'value' => '6')
  end

  def test_set_tracker_refuses_trackers_not_enabled_in_the_project
    assert_applied([{ 'type' => 'set_tracker', 'value' => '2' }])
    assert_equal 2, @issue.reload.tracker_id
    @project.trackers = [Tracker.find(1)]
    result, = run_actions([{ 'type' => 'set_tracker', 'value' => '3' }], Issue.find(1))
    assert_match(/not enabled/, result.error)
  end

  def test_set_and_clear_category
    assert_applied([{ 'type' => 'set_category', 'mode' => 'category', 'value' => '2' }])
    assert_equal 2, @issue.reload.category_id
    assert_applied([{ 'type' => 'set_category', 'mode' => 'clear' }], Issue.find(1))
    assert_nil @issue.reload.category_id
    assert_equal 'clear the category', describe('type' => 'set_category', 'mode' => 'clear')
  end

  def test_set_and_clear_target_version
    assert_applied([{ 'type' => 'set_target_version', 'mode' => 'version', 'value' => '3' }])
    assert_equal 3, @issue.reload.fixed_version_id
    result, = run_actions([{ 'type' => 'set_target_version', 'mode' => 'version', 'value' => '1' }], Issue.find(1))
    assert_match(/version #1 is not available/, result.error) # closed version
    assert_applied([{ 'type' => 'set_target_version', 'mode' => 'clear' }], Issue.find(1))
    assert_nil @issue.reload.fixed_version_id
  end

  def test_set_done_ratio_is_clamped
    assert_applied([{ 'type' => 'set_done_ratio', 'value' => '150' }])
    assert_equal 100, @issue.reload.done_ratio
    assert_equal 'set % done to 40%', describe('type' => 'set_done_ratio', 'value' => '40')
  end

  def test_set_private
    assert_applied([{ 'type' => 'set_private', 'value' => '1' }])
    assert @issue.reload.is_private?
    assert_applied([{ 'type' => 'set_private', 'value' => '0' }], Issue.find(1))
    assert_not @issue.reload.is_private?
  end

  # -- assignee -------------------------------------------------------------

  def test_set_assignee_modes
    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'user', 'user_id' => '3' }])
    assert_equal 3, @issue.reload.assigned_to_id

    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'author' }], Issue.find(1))
    assert_equal 2, @issue.reload.assigned_to_id

    User.current = User.find(3)
    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'current_user' }], Issue.find(1))
    assert_equal 3, @issue.reload.assigned_to_id
    User.current = nil

    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'unassign' }], Issue.find(1))
    assert_nil @issue.reload.assigned_to_id
    assert_equal 'assign to the author', describe('type' => 'set_assignee', 'mode' => 'author')
    assert_equal 'unassign', describe('type' => 'set_assignee', 'mode' => 'unassign')
  end

  def test_set_assignee_refuses_users_that_are_not_assignable
    result, = run_actions([{ 'type' => 'set_assignee', 'mode' => 'user', 'user_id' => '8' }])
    assert_match(/cannot be assigned/, result.error)
    assert_nil @issue.reload.assigned_to_id
  end

  def test_set_assignee_previous_uses_the_journal_history
    issue = Issue.find(2) # assigned to 3
    issue.init_journal(@author)
    issue.assigned_to_id = 2
    issue.save!
    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'previous' }], issue)
    assert_equal 3, issue.reload.assigned_to_id

    # No history: nothing changes.
    assert_applied([{ 'type' => 'set_assignee', 'mode' => 'previous' }], Issue.find(1))
    assert_nil Issue.find(1).assigned_to_id
  end

  def test_set_assignee_round_robin_rotates_among_assignable_group_members
    group = Group.create!(lastname: 'Rotation')
    group.users << User.find(2) << User.find(3) << User.find(8) # 8 is not a project member
    rule = build_rule(actions: [{ 'type' => 'set_assignee', 'mode' => 'round_robin', 'group_id' => group.id.to_s }])
    assigned = [1, 7, 3].map do |id|
      issue = Issue.find(id)
      result = RedmineAutomationRules::Runner.new(rule, issue).run
      assert result.success?, result.error
      issue.reload.assigned_to_id
    end
    assert_equal [2, 3, 2], assigned
    assert_equal({ 'rotation' => { group.id.to_s => 2 } }, rule.reload.state)
  end

  def test_set_assignee_round_robin_dry_run_does_not_advance
    group = Group.create!(lastname: 'Rotation')
    group.users << User.find(2) << User.find(3)
    rule = build_rule(actions: [{ 'type' => 'set_assignee', 'mode' => 'round_robin', 'group_id' => group.id.to_s }])
    result = RedmineAutomationRules::Runner.new(rule, @issue, dry_run: true).run
    assert result.success?, result.error
    assert_equal [nil, 2], result.changes['assigned_to_id']
    assert_equal({}, rule.reload.state)
    assert_nil @issue.reload.assigned_to_id
  end

  # -- dates ----------------------------------------------------------------

  def test_set_due_date_modes
    today = User.current.today
    assert_applied([{ 'type' => 'set_due_date', 'mode' => 'date', 'value' => '2030-01-15' }])
    assert_equal Date.new(2030, 1, 15), @issue.reload.due_date

    assert_applied([{ 'type' => 'set_due_date', 'mode' => 'today' }], Issue.find(1))
    assert_equal today, @issue.reload.due_date

    assert_applied([{ 'type' => 'set_due_date', 'mode' => 'relative', 'days' => '5' }], Issue.find(1))
    assert_equal today + 5, @issue.reload.due_date

    assert_applied([{ 'type' => 'set_due_date', 'mode' => 'from_other_date', 'days' => '3' }], Issue.find(1))
    assert_equal @issue.start_date + 3, @issue.reload.due_date

    assert_applied([{ 'type' => 'set_due_date', 'mode' => 'clear' }], Issue.find(1))
    assert_nil @issue.reload.due_date
    assert_equal 'set due date to 5 days from today',
                 describe('type' => 'set_due_date', 'mode' => 'relative', 'days' => '5')
  end

  def test_set_start_date_only_if_empty_and_working_day_shift
    issue = Issue.find(8) # no dates
    assert_applied([{ 'type' => 'set_start_date', 'mode' => 'today', 'only_if_empty' => '1' }], issue)
    assert_equal User.current.today, issue.reload.start_date

    assert_applied([{ 'type' => 'set_start_date', 'mode' => 'date', 'value' => '2030-01-01',
                      'only_if_empty' => '1' }], Issue.find(8))
    assert_equal User.current.today, issue.reload.start_date, 'kept because not empty'

    with_settings non_working_week_days: %w[6 7] do
      # 2030-01-05 is a Saturday: moved to Monday 2030-01-07.
      assert_applied([{ 'type' => 'set_start_date', 'mode' => 'date', 'value' => '2030-01-05',
                        'working_day' => '1' }], Issue.find(8))
    end
    assert_equal Date.new(2030, 1, 7), issue.reload.start_date
  end

  def test_set_due_date_with_invalid_date_is_an_error
    result, = run_actions([{ 'type' => 'set_due_date', 'mode' => 'date', 'value' => 'someday' }])
    assert_match(/invalid date/, result.error)
  end

  def test_working_days_helper
    days = RedmineAutomationRules::WorkingDays.new
    with_settings non_working_week_days: %w[6 7] do
      assert days.working_day?(Date.new(2030, 1, 4)) # Friday
      assert_not days.working_day?(Date.new(2030, 1, 5)) # Saturday
      assert_equal Date.new(2030, 1, 7), days.next_working_date(Date.new(2030, 1, 5))
      assert_equal Date.new(2030, 1, 4), days.previous_working_date(Date.new(2030, 1, 6))
      assert_equal Date.new(2030, 1, 4), days.next_working_date(Date.new(2030, 1, 4))
    end
  end

  # -- custom fields --------------------------------------------------------

  def test_set_custom_field_with_variables_and_date_macros
    field = IssueCustomField.create!(name: 'Note field', field_format: 'string', is_for_all: true,
                                     tracker_ids: [1, 2, 3])
    assert_applied([{ 'type' => 'set_custom_field', 'custom_field_id' => field.id.to_s,
                      'value' => '{{issue.author}} **YEAR**' }])
    assert_equal "John Smith #{User.current.today.year}", @issue.reload.custom_field_value(field)
    assert_equal 'set Note field to "{{issue.author}} **YEAR**"',
                 describe('type' => 'set_custom_field', 'custom_field_id' => field.id.to_s,
                          'value' => '{{issue.author}} **YEAR**')
  end

  def test_set_custom_field_date_and_list_and_user_formats
    date_field = IssueCustomField.create!(name: 'Reviewed on', field_format: 'date', is_for_all: true,
                                          tracker_ids: [1])
    assert_applied([{ 'type' => 'set_custom_field', 'custom_field_id' => date_field.id.to_s, 'value' => '**DATE+2**' }])
    assert_equal (User.current.today + 2).to_s, @issue.reload.custom_field_value(date_field)

    list_field = IssueCustomField.create!(name: 'Stale', field_format: 'list', possible_values: %w[yes no],
                                          is_for_all: true, tracker_ids: [1])
    assert_applied([{ 'type' => 'set_custom_field', 'custom_field_id' => list_field.id.to_s, 'value' => 'yes' }],
                   Issue.find(1))
    assert_equal 'yes', @issue.reload.custom_field_value(list_field)

    user_field = IssueCustomField.create!(name: 'Reviewer', field_format: 'user', is_for_all: true, tracker_ids: [1])
    assert_applied([{ 'type' => 'set_custom_field', 'custom_field_id' => user_field.id.to_s, 'value' => 'author' }],
                   Issue.find(1))
    assert_equal '2', @issue.reload.custom_field_value(user_field)
  end

  def test_set_custom_field_skips_issues_without_the_field_and_rejects_invalid_values
    field = IssueCustomField.create!(name: 'Only tracker 2', field_format: 'int', is_for_all: true, tracker_ids: [2])
    result, = assert_applied([{ 'type' => 'set_custom_field', 'custom_field_id' => field.id.to_s, 'value' => '7' }])
    assert_empty result.changes

    field.tracker_ids = [1, 2]
    field.save!
    result, = run_actions([{ 'type' => 'set_custom_field', 'custom_field_id' => field.id.to_s, 'value' => 'seven' }],
                          Issue.find(1))
    assert_not result.success?
    assert_match(/Only tracker 2/, result.error)

    result, = run_actions([{ 'type' => 'set_custom_field', 'custom_field_id' => '999', 'value' => '1' }], Issue.find(1))
    assert_match(/custom field not found/, result.error)
  end

  # -- watchers -------------------------------------------------------------

  def test_add_watchers_by_user_role_group_and_skips_users_without_visibility
    assert_applied([{ 'type' => 'add_watchers', 'who' => 'user', 'user_id' => '3' }])
    assert @issue.reload.watched_by?(User.find(3))

    assert_applied([{ 'type' => 'add_watchers', 'who' => 'role', 'role_id' => '1' }], Issue.find(1)) # Manager: user 2
    assert @issue.reload.watched_by?(User.find(2))

    group = Group.create!(lastname: 'Watching')
    group.users << User.find(8) # not a member, cannot see private/project issues? ecookbook is public
    assert_applied([{ 'type' => 'add_watchers', 'who' => 'group', 'group_id' => group.id.to_s }], Issue.find(1))
    assert Issue.find(1).watched_by?(User.find(8))

    @project.update!(is_public: false)
    Issue.find(1).remove_watcher(User.find(8))
    assert_applied([{ 'type' => 'add_watchers', 'who' => 'group', 'group_id' => group.id.to_s }], Issue.find(1))
    assert_not Issue.find(1).watched_by?(User.find(8))
    assert_equal 'add the Manager members as watchers',
                 describe('type' => 'add_watchers', 'who' => 'role', 'role_id' => '1')
  end

  def test_add_watchers_is_idempotent_and_dry_run_adds_nothing
    issue = Issue.find(2) # watched by 1 and 3
    assert_applied([{ 'type' => 'add_watchers', 'who' => 'user', 'user_id' => '3' }], issue)
    assert_equal 2, issue.reload.watchers.count

    result, = assert_applied([{ 'type' => 'add_watchers', 'who' => 'user', 'user_id' => '2' }], issue, dry_run: true)
    assert_equal ['add John Smith as watchers'], result.applied
    assert_equal 2, issue.reload.watchers.count
  end

  def test_remove_watchers
    issue = Issue.find(2) # watched by 1 and 3
    assert_applied([{ 'type' => 'remove_watchers', 'who' => 'user', 'user_id' => '3' }], issue)
    assert_equal [1], issue.reload.watcher_user_ids
    assert_applied([{ 'type' => 'remove_watchers', 'who' => 'all' }], issue)
    assert_empty issue.reload.watcher_user_ids
    assert_equal 'remove everybody from watchers', describe('type' => 'remove_watchers', 'who' => 'all')
  end

  # -- notes ----------------------------------------------------------------

  def test_add_note_substitutes_variables_and_date_macros
    assert_applied([{ 'type' => 'add_note', 'text' => 'Hi {{issue.assigned_to}}, #{{issue.id}} on **DATE**' }])
    assert_equal "Hi , #1 on #{User.current.today}", @issue.reload.journals.last.notes
  end

  # -- close / reopen ---------------------------------------------------------

  def test_close_issue_uses_the_first_allowed_closed_status
    assert_applied([{ 'type' => 'close_issue' }])
    assert_equal 5, @issue.reload.status_id
    assert @issue.closed?
    assert_equal 'close the issue', describe('type' => 'close_issue')
  end

  def test_close_issue_with_chosen_status_and_already_closed_is_a_no_op
    assert_applied([{ 'type' => 'close_issue', 'value' => '6' }])
    assert_equal 6, @issue.reload.status_id

    journals = Journal.count
    assert_applied([{ 'type' => 'close_issue' }], @closed)
    assert_equal journals, Journal.count
    assert_equal 5, @closed.reload.status_id
  end

  def test_close_issue_refused_when_the_workflow_offers_no_closed_status
    WorkflowTransition.where(role_id: 1, tracker_id: 1, new_status_id: [5, 6]).delete_all
    result, = run_actions([{ 'type' => 'close_issue' }])
    assert_match(/no closed status/, result.error)
    assert_equal 1, @issue.reload.status_id
  end

  def test_close_issue_refused_when_a_subtask_is_open
    child = Issue.generate!(project_id: 1, tracker_id: 1, parent_issue_id: 1, author_id: 2)
    assert child.reload.parent_id == 1
    result, = run_actions([{ 'type' => 'close_issue' }], Issue.find(1))
    assert_not result.success?
    assert_equal 1, Issue.find(1).status_id
  end

  def test_reopen_issue
    assert_applied([{ 'type' => 'reopen_issue' }], @closed)
    assert_equal 1, @closed.reload.status_id # tracker default status

    assert_applied([{ 'type' => 'reopen_issue', 'value' => '2' }], Issue.find(12))
    assert_equal 2, Issue.find(12).status_id

    journals = Journal.count
    assert_applied([{ 'type' => 'reopen_issue' }], Issue.find(1))
    assert_equal journals, Journal.count
    assert_equal 'reopen the issue as Assigned', describe('type' => 'reopen_issue', 'value' => '2')
  end

  # -- create issue -----------------------------------------------------------

  def test_create_subtask_from_template
    assert_applied([{ 'type' => 'create_issue', 'mode' => 'subtask', 'subject' => 'Review {{issue.subject}}',
                      'description' => 'Parent #{{issue.id}} by {{issue.author}}', 'tracker_id' => '2',
                      'who' => 'author' }])
    child = Issue.find(1).children.first
    assert_not_nil child
    assert_equal 'Review Cannot print recipes', child.subject
    assert_equal 'Parent #1 by John Smith', child.description
    assert_equal 2, child.tracker_id
    assert_equal 2, child.assigned_to_id
    assert_equal @author, child.author
    assert_equal 'create subtask "Review {{issue.subject}}"',
                 describe('type' => 'create_issue', 'mode' => 'subtask', 'subject' => 'Review {{issue.subject}}')
  end

  def test_create_related_issue
    assert_applied([{ 'type' => 'create_issue', 'mode' => 'related', 'relation_type' => 'blocks',
                      'subject' => 'Blocker for **YEAR**' }])
    relation = Issue.find(1).relations_to.detect { |r| r.relation_type == 'blocks' }
    assert_not_nil relation
    assert_equal "Blocker for #{User.current.today.year}", relation.issue_from.subject
    assert_equal 1, relation.issue_from.tracker_id
    assert_equal 'create issue "x" that blocks this issue',
                 describe('type' => 'create_issue', 'mode' => 'related', 'relation_type' => 'blocks', 'subject' => 'x')
  end

  def test_create_issue_is_skipped_in_dry_run_and_reports_validation_errors
    issues = Issue.count
    result, = assert_applied([{ 'type' => 'create_issue', 'mode' => 'subtask', 'subject' => 'Dry' }], dry_run: true)
    assert_equal ['create subtask "Dry"'], result.applied
    assert_equal issues, Issue.count

    result, rule = run_actions([{ 'type' => 'create_issue', 'mode' => 'subtask', 'subject' => 'x' * 300 }])
    assert result.success?, result.error # subject is truncated to fit
    assert_equal 255, Issue.find(1).children.first.subject.length
    assert_equal 1, rule.reload.runs_count
  end

  # -- email ------------------------------------------------------------------

  def test_send_email_to_users_roles_watchers_and_addresses
    ActionMailer::Base.deliveries.clear
    assert_applied([{ 'type' => 'send_email', 'who' => 'author', 'subject' => 'About #{{issue.id}}',
                      'body' => 'Due {{issue.due_date}}: {{issue.subject}}' },
                    { 'type' => 'send_email', 'who' => 'address', 'addresses' => 'a@example.com, b@example.com',
                      'subject' => 'Ext', 'body' => 'x' }])
    mails = ActionMailer::Base.deliveries
    assert_equal 3, mails.size
    mail = mails.first
    assert_equal ['jsmith@somenet.foo'], mail.to
    assert_equal 'About #1', mail.subject
    assert_include "Due #{@issue.due_date}: Cannot print recipes", text_part_body(mail)
    assert_include '/issues/1', text_part_body(mail)
    assert_equal [['a@example.com'], ['b@example.com']], mails.last(2).map(&:to)
    assert_equal 'send an email to the author', describe('type' => 'send_email', 'who' => 'author')
  end

  def test_send_email_is_not_sent_in_dry_run
    assert_applied([{ 'type' => 'send_email', 'who' => 'author', 'subject' => 's', 'body' => 'b' }], dry_run: true)
    assert_empty ActionMailer::Base.deliveries
  end

  # -- webhook ----------------------------------------------------------------

  def test_call_webhook_posts_json_with_signature
    requests = []
    RedmineAutomationRules::Webhook.transport = lambda do |uri, request|
      requests << [uri, request]
      Net::HTTPOK.new('1.1', '200', 'OK')
    end
    User.current = User.find(3)
    assert_applied([{ 'type' => 'call_webhook', 'url' => 'https://hooks.example.com/x?a=1', 'secret' => 's3cret' }])
    assert_equal 1, requests.size
    uri, request = requests.first
    assert_equal 'hooks.example.com', uri.host
    assert_equal 'application/json', request['Content-Type']
    assert_equal 's3cret', request['X-Automation-Rules-Secret']
    body = JSON.parse(request.body)
    assert_equal "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 's3cret', request.body)}",
                 request['X-Automation-Rules-Signature']
    assert_equal 'issue_updated', body['event']
    assert_equal 'Action rule', body.dig('rule', 'name')
    assert_equal 'Dave Lopper', body.dig('user', 'name')
    assert_equal 1, body.dig('issue', 'id')
    assert_equal 'Cannot print recipes', body.dig('issue', 'subject')
    assert_equal 'ecookbook', body.dig('project', 'identifier')
    assert_match(%r{/issues/1$}, body.dig('issue', 'url'))
    assert_equal 'call webhook https://hooks.example.com/x?a=1',
                 describe('type' => 'call_webhook', 'url' => 'https://hooks.example.com/x?a=1')
  end

  def test_call_webhook_without_secret_and_transport_errors_are_only_logged
    requests = []
    RedmineAutomationRules::Webhook.transport = lambda do |_uri, request|
      requests << request
      raise Errno::ECONNREFUSED
    end
    result, rule = run_actions([{ 'type' => 'call_webhook', 'url' => 'http://localhost:1/x' }])
    assert result.success?, result.error
    assert_equal 1, requests.size
    assert_nil requests.first['X-Automation-Rules-Secret']
    assert_nil requests.first['X-Automation-Rules-Signature']
    assert_nil rule.reload.last_error
  end

  def test_call_webhook_is_not_called_in_dry_run
    calls = 0
    RedmineAutomationRules::Webhook.transport = ->(_uri, _request) { calls += 1 }
    assert_applied([{ 'type' => 'call_webhook', 'url' => 'https://example.com/x' }], dry_run: true)
    assert_equal 0, calls
  end

  # -- parent -----------------------------------------------------------------

  def test_update_parent_closes_the_parent
    parent = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2, subject: 'Parent')
    child = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2, parent_issue_id: parent.id)
    child.init_journal(@author)
    child.status_id = 5
    child.save!
    assert_applied([{ 'type' => 'update_parent', 'action' => 'close_issue' }], child.reload,
                   rule_attributes: { note_marker: true })
    assert parent.reload.closed?

    assert_applied([{ 'type' => 'update_parent', 'action' => 'add_note', 'text' => 'Child {{issue.id}} done' }], child,
                   rule_attributes: { note_marker: true })
    assert_equal "Child #{child.id} done\n\n_(automation rule: Action rule)_", parent.reload.journals.last.notes
    assert_equal @author, parent.journals.last.user
    assert_equal 'on the parent issue: close the issue', describe('type' => 'update_parent', 'action' => 'close_issue')
  end

  def test_update_parent_without_parent_is_a_no_op_and_failures_are_recorded
    result, = assert_applied([{ 'type' => 'update_parent', 'action' => 'set_done_ratio', 'ratio' => '50' }])
    assert_equal ['on the parent issue: set % done to 50%'], result.applied

    parent = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2)
    Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2, parent_issue_id: parent.id) # stays open
    child = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2, parent_issue_id: parent.id)
    result, rule = run_actions([{ 'type' => 'update_parent', 'action' => 'close_issue' }], child.reload)
    assert_not result.success?
    assert_match(/no closed status/, result.error)
    assert_match(/no closed status/, rule.reload.last_error)
    assert_not parent.reload.closed?
  end

  # -- ordering, mixed and errors ---------------------------------------------

  def test_actions_run_in_order_and_stop_at_the_first_error
    result, = run_actions([{ 'type' => 'set_priority', 'value' => '6' },
                           { 'type' => 'set_status', 'value' => '999' },
                           { 'type' => 'add_note', 'text' => 'never' }])
    assert_equal ['set priority to High'], result.applied
    assert_match(/Action 2: status #999 not found/, result.error)
    assert_equal 4, @issue.reload.priority_id
    assert_empty @issue.journals.where(notes: 'never')
  end

  def test_side_effects_only_run_after_the_issue_was_saved
    calls = []
    RedmineAutomationRules::Webhook.transport = lambda do |_uri, request|
      calls << JSON.parse(request.body).dig('issue', 'status')
      Net::HTTPOK.new('1.1', '200', 'OK')
    end
    assert_applied([{ 'type' => 'call_webhook', 'url' => 'https://example.com/x' },
                    { 'type' => 'close_issue' }])
    assert_equal ['Closed'], calls
  end

  # -- date macros ------------------------------------------------------------

  def test_date_macros
    today = Date.new(2030, 3, 31) # Sunday, ISO week 13
    macros = RedmineAutomationRules::DateMacros
    assert_equal '2030-03-31', macros.apply('**DATE**', today)
    assert_equal '2030-04-07 31 03 2030 March 13 1',
                 macros.apply('**DATE+7** **DAY** **MONTH** **YEAR** **MONTHNAME** **WEEKISO** **QUARTER**', today)
    assert_equal '04 April 2030', macros.apply('**NEXT_MONTH** **NEXT_MONTHNAME** **NEXT_MONTH_YEAR**', today)
    assert_equal '02 February', macros.apply('**PREVIOUS_MONTH** **PREVIOUS_MONTHNAME**', today)
    assert_equal '14 2030', macros.apply('**NEXT_WEEKISO** **NEXT_WEEKISO_YEAR**', today)
    assert_equal '2030-03-24', macros.apply('**DATE-7**', today)
    assert_equal 'no macros here', macros.apply('no macros here', today)
    assert_equal '**UNKNOWN**', macros.apply('**UNKNOWN**', today)
  end

  private

  def text_part_body(mail)
    (mail.text_part || mail).body.decoded
  end
end
