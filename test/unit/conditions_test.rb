require "#{File.dirname(__FILE__)}/../test_helper"

class ConditionsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues, :issue_categories, :versions, :watchers,
           :time_entries, :groups_users, :custom_fields, :custom_values,
           :custom_fields_trackers, :custom_fields_projects

  Conditions = RedmineAutomationRules::Conditions

  def setup
    User.current = User.find(2)
    @issue = Issue.find(1) # Bug, New, Low, author 2, unassigned, category 1, 154.25h spent
    @issue2 = Issue.find(2) # Feature, Assigned, Normal, assigned to 3, version 2, 2 watchers
  end

  def teardown
    User.current = nil
  end

  def match?(type, issue = @issue, context: {}, **params)
    Conditions.matches?({ 'type' => type.to_s }.merge(params.transform_keys(&:to_s)), issue, context)
  end

  def describe(type, **params)
    Conditions.build({ 'type' => type.to_s }.merge(params.transform_keys(&:to_s))).describe
  end

  # --- registry -------------------------------------------------------------

  def test_every_condition_type_is_registered_with_a_label_and_operators
    expected = %w[tracker status priority assignee author category target_version done_ratio due_date start_date
                  subject description watchers_count parent subtasks private time_spent updated_ago created_ago
                  custom_field]
    assert_equal expected.sort, Conditions.all.map(&:key).sort
    Conditions.all.each do |klass|
      assert klass.operators.any?, "#{klass.key} has no operators"
      assert_no_match(/translation missing/i, klass.label, klass.key)
      klass.operators.each do |op|
        assert_no_match(/translation missing/i, ::I18n.t("automation_rules_operator_#{op}"), "#{klass.key}/#{op}")
      end
    end
  end

  def test_schema_lists_params_with_translated_labels
    schema = Conditions.schema(Project.find(1))
    assignee = schema.find { |c| c['key'] == 'assignee' }
    assert_equal(%w[operator value group_id], assignee['params'].map { |param| param['name'] })
    assert_equal({ 'operator' => %w[in_group not_in_group] }, assignee['params'].last['when'])
    assert_equal 'user', assignee['params'][1]['options']
  end

  def test_unknown_type_never_matches
    assert_not Conditions.matches?({ 'type' => 'nope' }, @issue)
    assert_nil Conditions.build({ 'type' => 'nope' })
  end

  def test_required_params_and_regexps_are_validated
    assert_equal ['value cannot be blank'], Conditions.build('type' => 'tracker', 'operator' => 'is').validate
    assert_empty Conditions.build('type' => 'status', 'operator' => 'is_closed').validate
    invalid = Conditions.build('type' => 'subject', 'operator' => 'matches', 'value' => '(')
    assert_match(/invalid regular expression/, invalid.validate.first)
    assert_empty Conditions.build('type' => 'subject', 'operator' => 'matches', 'value' => 'a+').validate
  end

  # --- tracker / status / priority -----------------------------------------

  def test_tracker
    assert match?(:tracker, operator: 'is', value: '1')
    assert_not match?(:tracker, operator: 'is', value: '2')
    assert match?(:tracker, operator: 'is_not', value: '2')
    assert_equal 'tracker is Bug', describe(:tracker, operator: 'is', value: '1')
  end

  def test_status
    assert match?(:status, operator: 'is', value: '1')
    assert match?(:status, operator: 'is_open')
    assert_not match?(:status, operator: 'is_closed')
    @issue.status = IssueStatus.find(5)
    assert match?(:status, operator: 'is_closed')
    assert_equal 'status is closed', describe(:status, operator: 'is_closed', value: '1')
  end

  def test_priority
    assert match?(:priority, operator: 'is', value: '4')
    assert match?(:priority, operator: 'is_at_most', value: '5')
    assert_not match?(:priority, operator: 'is_at_least', value: '5')
    assert match?(:priority, @issue2, operator: 'is_at_least', value: '5')
  end

  # --- people ---------------------------------------------------------------

  def test_assignee
    assert match?(:assignee, operator: 'is_nobody')
    assert_not match?(:assignee, operator: 'is_anybody')
    assert match?(:assignee, @issue2, operator: 'is', value: '3')
    assert match?(:assignee, @issue2, operator: 'is_not', value: '2')
    assert_not match?(:assignee, @issue2, operator: 'is_author')
    @issue2.assigned_to = @issue2.author
    assert match?(:assignee, @issue2, operator: 'is_author')
    assert match?(:assignee, @issue2, operator: 'is_current_user', context: { actor: User.find(2) })
    assert_not match?(:assignee, @issue2, operator: 'is_current_user', context: { actor: User.find(3) })
    assert_equal 'assignee is Dave Lopper', describe(:assignee, operator: 'is', value: '3')
  end

  def test_assignee_group_membership
    @issue.assigned_to = User.find(8) # member of groups 10 and 11
    assert match?(:assignee, operator: 'in_group', group_id: '10')
    assert_not match?(:assignee, operator: 'not_in_group', group_id: '11')
    @issue.assigned_to = User.find(2) # no groups
    assert_not match?(:assignee, operator: 'in_group', group_id: '10')
    assert match?(:assignee, operator: 'not_in_group', group_id: '11')
    @issue.assigned_to = nil
    assert_not match?(:assignee, operator: 'in_group', group_id: '10')
    assert match?(:assignee, operator: 'not_in_group', group_id: '10')
    assert_equal 'assignee is in group A Team', describe(:assignee, operator: 'in_group', group_id: '10')
  end

  def test_author
    assert match?(:author, operator: 'is', value: '2')
    assert match?(:author, operator: 'is_not', value: '3')
    assert match?(:author, operator: 'is_current_user', context: { actor: User.find(2) })
    assert_not match?(:author, operator: 'is_current_user', context: { actor: User.find(3) })
    assert_not match?(:author, operator: 'in_group', group_id: '10')
    assert match?(:author, operator: 'not_in_group', group_id: '10')
    @issue.author = User.find(8)
    assert match?(:author, operator: 'in_group', group_id: '10')
    assert_not match?(:author, operator: 'not_in_group', group_id: '11')
  end

  def test_current_user_falls_back_to_the_running_user_without_an_actor
    assert match?(:author, operator: 'is_current_user')
    User.current = User.find(3)
    assert_not match?(:author, operator: 'is_current_user')
  end

  # --- classification -------------------------------------------------------

  def test_category
    assert match?(:category, operator: 'is', value: '1')
    assert match?(:category, operator: 'is_set')
    assert match?(:category, @issue2, operator: 'is_empty')
    assert match?(:category, @issue2, operator: 'is_not', value: '1')
    assert_equal 'category is Printing', describe(:category, operator: 'is', value: '1')
  end

  def test_target_version
    assert match?(:target_version, operator: 'is_empty')
    assert match?(:target_version, @issue2, operator: 'is', value: '2')
    assert match?(:target_version, @issue2, operator: 'is_set')
    assert_not match?(:target_version, @issue2, operator: 'is_open') # version 2 is locked
    assert_not match?(:target_version, @issue2, operator: 'is_closed')
    @issue2.fixed_version = Version.find(1)
    assert match?(:target_version, @issue2, operator: 'is_closed')
    assert_equal 'target version is 1.0', describe(:target_version, operator: 'is', value: '2')
  end

  def test_done_ratio
    @issue.done_ratio = 50
    assert match?(:done_ratio, operator: 'eq', value: '50')
    assert match?(:done_ratio, operator: 'gte', value: '50')
    assert match?(:done_ratio, operator: 'lt', value: '51')
    assert_not match?(:done_ratio, operator: 'gt', value: '50')
    assert match?(:done_ratio, operator: 'lte', value: '50')
    assert_equal '% done >= 50%', describe(:done_ratio, operator: 'gte', value: '50')
  end

  def test_private
    assert match?(:private, operator: 'is_public')
    @issue.is_private = true
    assert match?(:private, operator: 'is_private')
    assert_equal 'private flag is private', describe(:private, operator: 'is_private')
  end

  # --- dates ----------------------------------------------------------------

  def test_due_date_and_start_date
    today = User.current.today
    @issue.due_date = nil
    assert match?(:due_date, operator: 'is_empty')
    assert_not match?(:due_date, operator: 'is_past')
    @issue.due_date = today - 3
    assert match?(:due_date, operator: 'is_set')
    assert match?(:due_date, operator: 'is_past')
    assert match?(:due_date, operator: 'more_than_days_ago', days: '2')
    assert_not match?(:due_date, operator: 'more_than_days_ago', days: '3')
    @issue.due_date = today
    assert match?(:due_date, operator: 'is_today')
    assert match?(:due_date, operator: 'within_days', days: '0')
    @issue.due_date = today + 2
    assert match?(:due_date, operator: 'within_days', days: '2')
    assert_not match?(:due_date, operator: 'within_days', days: '1')
    assert match?(:due_date, operator: 'more_than_days_ahead', days: '1')

    @issue.start_date = today + 5
    assert match?(:start_date, operator: 'more_than_days_ahead', days: '4')
    assert_equal 'due date is within the next 2 days', describe(:due_date, operator: 'within_days', days: '2')
    assert_equal 'start date is empty', describe(:start_date, operator: 'is_empty')
  end

  def test_updated_and_created_ago
    @issue.updated_on = 10.days.ago + 1.hour
    @issue.created_on = 3.hours.ago
    assert match?(:updated_ago, operator: 'more_than_days', value: '9')
    assert_not match?(:updated_ago, operator: 'more_than_days', value: '10')
    assert match?(:updated_ago, operator: 'less_than_days', value: '11')
    assert match?(:created_ago, operator: 'more_than_hours', value: '2')
    assert match?(:created_ago, operator: 'less_than_hours', value: '4')
    assert_not match?(:created_ago, operator: 'more_than_days', value: '1')
    assert_equal 'last updated more than 9 days ago', describe(:updated_ago, operator: 'more_than_days', value: '9')
    assert_equal 'created more than 1 hour ago', describe(:created_ago, operator: 'more_than_hours', value: '1')
  end

  # --- text -----------------------------------------------------------------

  def test_subject_and_description
    assert match?(:subject, operator: 'contains', value: 'PRINT')
    assert match?(:subject, operator: 'not_contains', value: 'ingredients')
    assert match?(:subject, operator: 'starts_with', value: 'cannot')
    assert match?(:subject, operator: 'matches', value: '^Cannot .* recipes$')
    assert match?(:subject, operator: 'not_matches', value: '\d+')
    assert match?(:subject, operator: 'is', value: 'cannot print recipes')
    assert match?(:subject, operator: 'is_not', value: 'other')
    @issue.description = nil
    assert_not match?(:description, operator: 'contains', value: 'x')
    @issue.description = "Line one\nERROR 42"
    assert match?(:description, operator: 'matches', value: 'error \d+')
    assert_equal 'subject contains "print"', describe(:subject, operator: 'contains', value: 'print')
  end

  # --- relations ------------------------------------------------------------

  def test_watchers_count
    assert match?(:watchers_count, operator: 'eq', value: '0')
    assert match?(:watchers_count, @issue2, operator: 'eq', value: '2')
    assert match?(:watchers_count, @issue2, operator: 'gte', value: '2')
    assert_not match?(:watchers_count, @issue2, operator: 'gt', value: '2')
    assert_equal 'number of watchers > 1', describe(:watchers_count, operator: 'gt', value: '1')
  end

  def test_parent_and_subtasks
    parent = Issue.find(1)
    assert match?(:parent, parent, operator: 'no_parent')
    assert match?(:subtasks, parent, operator: 'none')
    assert_not match?(:subtasks, parent, operator: 'all_closed')

    child = Issue.generate!(project_id: 1, tracker_id: 1, author_id: 2, subject: 'child', parent_issue_id: parent.id)
    parent.reload
    assert match?(:parent, child, operator: 'has_parent')
    assert match?(:parent, child, operator: 'parent_is_open')
    assert_not match?(:parent, child, operator: 'parent_is_closed')
    assert match?(:subtasks, parent, operator: 'any')
    assert match?(:subtasks, parent, operator: 'any_open')
    assert_not match?(:subtasks, parent, operator: 'all_closed')

    child.update_columns(status_id: 5, closed_on: Time.current)
    parent.reload
    assert match?(:subtasks, parent, operator: 'all_closed')
    assert_not match?(:subtasks, parent, operator: 'any_open')
    assert_equal 'subtasks are all closed', describe(:subtasks, operator: 'all_closed')
    assert_equal 'parent issue has a parent', describe(:parent, operator: 'has_parent')
  end

  # --- time -----------------------------------------------------------------

  def test_time_spent
    assert match?(:time_spent, operator: 'gt_hours', value: '154')
    assert_not match?(:time_spent, operator: 'gt_hours', value: '155')
    assert match?(:time_spent, operator: 'lt_hours', value: '155')
    assert_not match?(:time_spent, operator: 'gt_estimated') # no estimate
    @issue.estimated_hours = 100
    assert match?(:time_spent, operator: 'gt_estimated')
    assert_not match?(:time_spent, operator: 'lte_estimated')
    @issue.estimated_hours = 200
    assert match?(:time_spent, operator: 'lte_estimated')
    assert match?(:time_spent, @issue2, operator: 'none')
    assert_match(/\Atime spent is more than 2/, describe(:time_spent, operator: 'gt_hours', value: '2'))
  end

  # --- custom fields --------------------------------------------------------

  def test_custom_field_string_list_and_float
    # CF 2 "Searchable field" (string) = "125" on issue 1; CF 6 "Float field" = 2.1
    assert match?(:custom_field, custom_field_id: '2', operator: 'is', value: '125')
    assert match?(:custom_field, custom_field_id: '2', operator: 'is_not', value: '126')
    assert match?(:custom_field, custom_field_id: '2', operator: 'is_set')
    assert match?(:custom_field, custom_field_id: '2', operator: 'contains', value: '12')
    assert match?(:custom_field, custom_field_id: '2', operator: 'matches', value: '^\d{3}$')
    assert match?(:custom_field, custom_field_id: '2', operator: 'gt', value: '124') # string comparison
    assert match?(:custom_field, custom_field_id: '6', operator: 'gt', value: '2')
    assert match?(:custom_field, custom_field_id: '6', operator: 'lte', value: '2.1')
    assert_not match?(:custom_field, custom_field_id: '6', operator: 'gte', value: '2.2')
    assert match?(:custom_field, custom_field_id: '6', operator: 'is', value: '2.10')

    issue3 = Issue.find(3) # Database = MySQL
    assert match?(:custom_field, issue3, custom_field_id: '1', operator: 'is', value: 'MySQL')
    assert match?(:custom_field, issue3, custom_field_id: '1', operator: 'is_not', value: 'PostgreSQL')
    assert_not match?(:custom_field, @issue2, custom_field_id: '2', operator: 'is_empty') # not on tracker 2
    assert_equal 'Searchable field is 125', describe(:custom_field, custom_field_id: '2', operator: 'is', value: '125')
  end

  def test_custom_field_int_bool_and_date
    int_cf = IssueCustomField.create!(name: 'Points', field_format: 'int', is_for_all: true, trackers: Tracker.all)
    bool_cf = IssueCustomField.create!(name: 'Stale', field_format: 'bool', is_for_all: true, trackers: Tracker.all)
    date_cf = IssueCustomField.find(8) # "Custom date"
    issue = Issue.find(1)
    today = User.current.today
    issue.custom_field_values = { int_cf.id => '7', bool_cf.id => '1', date_cf.id => (today - 5).to_s }

    assert match?(:custom_field, issue, custom_field_id: int_cf.id, operator: 'gt', value: '6')
    assert match?(:custom_field, issue, custom_field_id: int_cf.id, operator: 'is', value: '07')
    assert_not match?(:custom_field, issue, custom_field_id: int_cf.id, operator: 'lt', value: '7')

    assert match?(:custom_field, issue, custom_field_id: bool_cf.id, operator: 'is', value: '1')
    assert match?(:custom_field, issue, custom_field_id: bool_cf.id, operator: 'is_not', value: '0')
    issue.custom_field_values = { bool_cf.id => '0' }
    assert match?(:custom_field, issue, custom_field_id: bool_cf.id, operator: 'is', value: '0')

    assert match?(:custom_field, issue, custom_field_id: date_cf.id, operator: 'is_past')
    assert match?(:custom_field, issue, custom_field_id: date_cf.id, operator: 'more_than_days_ago', days: '4')
    assert_not match?(:custom_field, issue, custom_field_id: date_cf.id, operator: 'within_days', days: '10')
    assert match?(:custom_field, issue, custom_field_id: date_cf.id, operator: 'lt', value: (today - 4).to_s)
    assert match?(:custom_field, issue, custom_field_id: date_cf.id, operator: 'is', value: (today - 5).to_s)
    assert_equal 'Custom date is older than 4 days',
                 describe(:custom_field, custom_field_id: date_cf.id, operator: 'more_than_days_ago', days: '4')
  end

  def test_custom_field_user_and_version
    user_cf = IssueCustomField.create!(name: 'Reviewer', field_format: 'user', is_for_all: true, trackers: Tracker.all)
    version_cf = IssueCustomField.create!(name: 'Found in', field_format: 'version', is_for_all: true,
                                          trackers: Tracker.all)
    issue = Issue.find(2) # author 2, assigned to 3
    issue.custom_field_values = { user_cf.id => '3', version_cf.id => '2' }

    assert match?(:custom_field, issue, custom_field_id: user_cf.id, operator: 'is', value: '3')
    assert match?(:custom_field, issue, custom_field_id: user_cf.id, operator: 'is_assignee')
    assert_not match?(:custom_field, issue, custom_field_id: user_cf.id, operator: 'is_author')
    assert match?(:custom_field, issue, custom_field_id: user_cf.id, operator: 'is_current_user',
                                        context: { actor: User.find(3) })
    assert match?(:custom_field, issue, custom_field_id: version_cf.id, operator: 'is', value: '2')
    assert match?(:custom_field, issue, custom_field_id: version_cf.id, operator: 'is_not', value: '3')
    assert_equal 'Reviewer is Dave Lopper', describe(:custom_field, custom_field_id: user_cf.id, operator: 'is',
                                                                    value: '3')
  end

  def test_custom_field_multiple_values
    cf = IssueCustomField.create!(name: 'Tags', field_format: 'list', multiple: true, is_for_all: true,
                                  possible_values: %w[red green blue], trackers: Tracker.all)
    issue = Issue.find(1)
    issue.custom_field_values = { cf.id => %w[red blue] }
    assert match?(:custom_field, issue, custom_field_id: cf.id, operator: 'is', value: 'blue')
    assert_not match?(:custom_field, issue, custom_field_id: cf.id, operator: 'is', value: 'green')
    assert match?(:custom_field, issue, custom_field_id: cf.id, operator: 'is_not', value: 'green')
    assert match?(:custom_field, issue, custom_field_id: cf.id, operator: 'contains', value: 'red')
    issue.custom_field_values = { cf.id => [''] }
    assert match?(:custom_field, issue, custom_field_id: cf.id, operator: 'is_empty')
  end

  def test_custom_field_unknown_or_unavailable_never_matches_and_is_reported
    assert_not match?(:custom_field, custom_field_id: '999', operator: 'is_set')
    assert_not match?(:custom_field, custom_field_id: '999', operator: 'is_empty')
    assert_equal ['custom field not found'],
                 Conditions.build('type' => 'custom_field', 'custom_field_id' => '999', 'operator' => 'is_set').validate
    assert_equal ['value cannot be blank'],
                 Conditions.build('type' => 'custom_field', 'custom_field_id' => '2', 'operator' => 'is').validate
  end

  # --- rule integration -----------------------------------------------------

  def test_rule_validation_reports_condition_errors_with_position
    rule = AutomationRule.new(project: Project.find(1), author: User.find(2), name: 'x', trigger_type: 'issue_created',
                              conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' },
                                           { 'type' => 'subject', 'operator' => 'matches', 'value' => '[' }])
    assert_not rule.valid?
    assert_match(/Condition 2: invalid regular expression/, rule.errors.full_messages.join)
  end
end
