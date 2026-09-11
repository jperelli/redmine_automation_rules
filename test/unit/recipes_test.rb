require "#{File.dirname(__FILE__)}/../test_helper"

class RecipesTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :groups_users,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :workflows, :custom_fields, :custom_fields_trackers

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['automation_rules']
    @user = User.find(2)
    User.current = nil
    RedmineAutomationRules::Events.synchronous = true
  end

  def teardown
    RedmineAutomationRules::Events.synchronous = nil
    User.current = nil
  end

  def test_keys_and_options_are_in_sync
    assert_equal 11, RedmineAutomationRules::Recipes.keys.size
    options = RedmineAutomationRules::Recipes.options
    assert_equal RedmineAutomationRules::Recipes.keys, options.map(&:last)
    options.each { |label, key| assert_no_match(/translation missing/, label, key) }
  end

  def test_unknown_recipe_builds_nothing
    assert_nil RedmineAutomationRules::Recipes.build('nope', project: @project, user: @user)
    rule = AutomationRule.new(project: @project, author: @user)
    assert_not rule.apply_recipe('nope')
  end

  RedmineAutomationRules::Recipes::KEYS.each do |key|
    define_method("test_recipe_#{key}_builds_a_valid_project_rule") do
      rule = AutomationRule.new(project: @project, author: @user)
      assert rule.apply_recipe(key, @user)
      assert rule.valid?, "#{key}: #{rule.errors.full_messages.join(', ')}"
      assert rule.name.present?
      assert rule.description.present?
      assert_no_match(/translation missing/, rule.sentence)
      assert rule.actions.any?, "#{key} has no actions"
      assert rule.save
    end

    define_method("test_recipe_#{key}_builds_a_valid_global_rule") do
      rule = AutomationRule.new(project: nil, author: User.find(1))
      assert rule.apply_recipe(key, User.find(1))
      assert rule.valid?, "#{key}: #{rule.errors.full_messages.join(', ')}"
    end
  end

  def test_recipes_look_up_statuses_priorities_roles_and_groups_by_name
    attrs = RedmineAutomationRules::Recipes.build('auto_close_resolved', project: @project, user: @user)
    assert_equal 'scheduled', attrs['trigger_type']
    assert_equal IssueStatus.find_by(name: 'Resolved').id.to_s, attrs['conditions'].first['value']
    assert_equal 'close_issue', attrs['actions'].last['type']

    attrs = RedmineAutomationRules::Recipes.build('escalate_unassigned_high_priority', project: @project, user: @user)
    assert_equal IssuePriority.find_by(name: 'High').id.to_s, attrs['conditions'].first['value']
    assert_equal Role.find_by(name: 'Manager').id.to_s, attrs['actions'].first['role_id']

    attrs = RedmineAutomationRules::Recipes.build('round_robin_unassigned', project: @project, user: @user)
    assert_equal 'round_robin', attrs['actions'].first['mode']
    assert_equal Group.givable.sorted.first.id.to_s, attrs['actions'].first['group_id']
  end

  def test_recipes_fall_back_when_names_are_missing
    IssueStatus.find_by(name: 'Resolved').update_column(:name, 'Done')
    attrs = RedmineAutomationRules::Recipes.build('auto_close_resolved', project: @project, user: @user)
    assert_equal IssueStatus.sorted.find_by(is_closed: false).id.to_s, attrs['conditions'].first['value']

    Group.givable.destroy_all
    attrs = RedmineAutomationRules::Recipes.build('round_robin_unassigned', project: @project, user: @user)
    assert_equal 'author', attrs['actions'].first['mode']
  end

  def test_assign_by_category_uses_the_first_project_category
    category = @project.issue_categories.first
    attrs = RedmineAutomationRules::Recipes.build('assign_by_category', project: @project, user: @user)
    assert_equal category.id.to_s, attrs['conditions'].first['value']
    assert_equal (category.assigned_to || @user).id.to_s, attrs['actions'].first['user_id']

    attrs = RedmineAutomationRules::Recipes.build('assign_by_category', project: nil, user: @user)
    assert_equal 'is_set', attrs['conditions'].first['operator']
    assert_equal @user.id.to_s, attrs['actions'].first['user_id']
  end

  def test_stale_issues_sets_the_custom_field_only_when_it_exists
    attrs = RedmineAutomationRules::Recipes.build('stale_issues', project: @project, user: @user)
    assert_equal(['add_note'], attrs['actions'].map { |a| a['type'] })

    cf = IssueCustomField.create!(name: 'Stale', field_format: 'bool', is_for_all: true, trackers: Tracker.all)
    attrs = RedmineAutomationRules::Recipes.build('stale_issues', project: @project, user: @user)
    assert_equal(%w[add_note set_custom_field], attrs['actions'].map { |a| a['type'] })
    assert_equal cf.id.to_s, attrs['actions'].last['custom_field_id']
  end

  def test_close_parent_recipe_closes_the_parent_once_the_last_subtask_is_closed
    parent = Issue.generate!(project: @project, tracker_id: 1, author: @user, subject: 'Parent')
    first = Issue.generate!(project: @project, tracker_id: 1, author: @user, subject: 'Sub 1',
                            parent_issue_id: parent.id)
    second = Issue.generate!(project: @project, tracker_id: 1, author: @user, subject: 'Sub 2',
                             parent_issue_id: parent.id)
    rule = AutomationRule.new(project: @project, author: @user)
    rule.apply_recipe('close_parent_when_subtasks_closed', @user)
    rule.save!
    closed = IssueStatus.where(is_closed: true).first

    User.current = @user
    first.init_journal(@user)
    first.status = closed
    first.save!
    assert_not parent.reload.closed?, 'parent closed while a subtask is still open'

    second.init_journal(@user)
    second.status = closed
    second.save!
    assert parent.reload.closed?
  end
end
