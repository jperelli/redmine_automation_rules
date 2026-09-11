require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRuleTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issues

  def setup
    @project = Project.find(1)
    @subproject = Project.find(3) # child of ecookbook
    @author = User.find(2)
    @project.enabled_module_names = @project.enabled_module_names | ['automation_rules']
    Role.find(1).add_permission!(:manage_automation_rules)
  end

  def build_rule(attributes = {})
    AutomationRule.new({ project: @project, author: @author, name: 'Rule',
                         trigger_type: 'issue_created' }.merge(attributes))
  end

  # --- validations -----------------------------------------------------------

  def test_requires_name_author_and_known_trigger
    rule = AutomationRule.new
    assert_not rule.valid?
    assert rule.errors[:name].any?
    assert rule.errors[:author].any?
    assert rule.errors[:trigger_type].any?

    rule = build_rule(trigger_type: 'bogus')
    assert_not rule.valid?
    assert rule.errors[:trigger_type].any?
  end

  def test_scheduled_rule_requires_a_valid_interval
    rule = build_rule(trigger_type: 'scheduled', trigger_options: {})
    assert_not rule.valid?
    assert rule.errors[:trigger_options].any?

    rule.trigger_options = { 'interval_number' => '0', 'interval_unit' => 'hour' }
    assert_not rule.valid?

    rule.trigger_options = { 'interval_number' => '2', 'interval_unit' => 'hour' }
    assert rule.valid?, rule.errors.full_messages.to_sentence

    rule.trigger_options = { 'interval_number' => '1', 'interval_unit' => 'day', 'time_of_day' => '25:00' }
    assert_not rule.valid?

    rule.trigger_options = { 'interval_number' => '1', 'interval_unit' => 'day', 'time_of_day' => '09:30' }
    assert rule.valid?
  end

  def test_unknown_condition_and_action_types_are_rejected
    rule = build_rule(conditions: [{ 'type' => 'nope' }], actions: [{ 'type' => 'explode' }])
    assert_not rule.valid?
    messages = rule.errors.full_messages
    assert messages.any? { |m| m.include?("unknown type 'nope'") }, messages.inspect
    assert messages.any? { |m| m.include?("unknown type 'explode'") }, messages.inspect
  end

  def test_required_params_are_validated_per_row
    rule = build_rule(conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '' }],
                      actions: [{ 'type' => 'add_note', 'text' => '' }])
    assert_not rule.valid?
    messages = rule.errors.full_messages
    assert messages.any? { |m| m.start_with?('Condition 1:') }, messages.inspect
    assert messages.any? { |m| m.start_with?('Action 1:') }, messages.inspect
  end

  def test_conditional_params_are_only_required_when_visible
    rule = build_rule(conditions: [{ 'type' => 'status', 'operator' => 'is_closed' }])
    assert rule.valid?, rule.errors.full_messages.to_sentence
  end

  # --- JSON storage ----------------------------------------------------------

  def test_conditions_and_actions_round_trip_through_text_columns
    rule = build_rule(conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }],
                      actions: [{ 'type' => 'set_status', 'value' => '5' },
                                { 'type' => 'add_note', 'text' => 'Hello' }])
    assert rule.save, rule.errors.full_messages.to_sentence
    rule = AutomationRule.find(rule.id)
    assert_equal [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }], rule.conditions
    assert_equal(%w[set_status add_note], rule.actions.map { |a| a['type'] })
    assert_equal 'text', AutomationRule.columns_hash['conditions'].type.to_s
  end

  def test_rows_accept_indexed_hashes_from_forms_and_drop_blank_rows
    rule = build_rule
    rule.conditions = { '1' => { 'type' => 'status', 'operator' => 'is_open' },
                        '0' => { 'type' => 'tracker', 'value' => '1' }, '2' => { 'type' => '' } }
    assert_equal(%w[tracker status], rule.conditions.map { |c| c['type'] })

    rule.actions = ActionController::Parameters.new('0' => { 'type' => 'add_note', 'text' => 'x' })
    assert_equal [{ 'type' => 'add_note', 'text' => 'x' }], rule.actions

    rule.actions = '[{"type":"add_note","text":"json"}]'
    assert_equal 'json', rule.actions.first['text']

    rule.actions = 'not json'
    assert_equal [], rule.actions
  end

  def test_trigger_options_are_stringified
    rule = build_rule(trigger_type: 'issue_updated', trigger_options: { change: 'status_to', status_id: 5 })
    assert rule.save
    assert_equal({ 'change' => 'status_to', 'status_id' => 5 }, rule.reload.trigger_options)
    assert_equal 'status_to', rule.trigger_option(:change)
  end

  def test_trigger_options_of_other_trigger_types_are_dropped_on_save
    submitted = { 'change' => 'status_to', 'field' => 'due_date', 'status_id' => '5',
                  'interval_number' => '3', 'interval_unit' => 'hour', 'time_of_day' => '09:00' }

    rule = build_rule(trigger_type: 'issue_updated', trigger_options: submitted)
    assert rule.save
    assert_equal({ 'change' => 'status_to', 'status_id' => '5' }, rule.reload.trigger_options)

    rule = build_rule(trigger_type: 'issue_updated', trigger_options: submitted.merge('change' => 'field'))
    assert rule.save
    assert_equal({ 'change' => 'field', 'field' => 'due_date' }, rule.reload.trigger_options)

    rule = build_rule(trigger_type: 'scheduled', trigger_options: submitted)
    assert rule.save
    assert_equal({ 'interval_number' => '3', 'interval_unit' => 'hour' }, rule.reload.trigger_options)

    rule = build_rule(trigger_type: 'scheduled', trigger_options: submitted.merge('interval_unit' => 'day'))
    assert rule.save
    assert_equal({ 'interval_number' => '3', 'interval_unit' => 'day', 'time_of_day' => '09:00' },
                 rule.reload.trigger_options)

    rule = build_rule(trigger_type: 'issue_closed', trigger_options: submitted)
    assert rule.save
    assert_equal({}, rule.reload.trigger_options)
  end

  # --- scope ----------------------------------------------------------------

  def test_global_rule_has_no_project_and_applies_everywhere
    rule = build_rule(project: nil)
    assert rule.save
    assert rule.global?
    assert rule.applies_to?(@project)
    assert rule.applies_to?(Project.find(2))
    assert_not rule.applies_to?(nil)
  end

  def test_project_rule_applies_to_subprojects_only_when_flagged
    rule = build_rule
    assert rule.applies_to?(@project)
    assert_not rule.applies_to?(@subproject)
    assert_not rule.applies_to?(Project.find(2))

    rule.apply_to_subprojects = true
    assert rule.applies_to?(@subproject)
    assert_not rule.applies_to?(Project.find(2))
  end

  def test_applicable_to_scope_includes_global_own_and_inherited_rules
    global = build_rule(project: nil, name: 'global')
    own = build_rule(name: 'own')
    parent_flagged = build_rule(name: 'parent flagged', apply_to_subprojects: true)
    parent_plain = build_rule(name: 'parent plain')
    other = build_rule(project: Project.find(2), name: 'other')
    [global, own, parent_flagged, parent_plain, other].each { |r| assert r.save, r.errors.full_messages.to_sentence }

    names = AutomationRule.applicable_to(@subproject).map(&:name)
    assert_includes names, 'global'
    assert_includes names, 'parent flagged'
    assert_not_includes names, 'parent plain'
    assert_not_includes names, 'other'

    names = AutomationRule.applicable_to(@project).map(&:name)
    assert_equal ['global', 'own', 'parent flagged', 'parent plain'], names.sort
  end

  def test_candidate_issues_follow_the_rule_scope
    project_rule = build_rule
    assert_equal Issue.open.where(project_id: 1).pluck(:id).sort, project_rule.candidate_issues.pluck(:id).sort

    with_subprojects = build_rule(apply_to_subprojects: true)
    ids = Issue.open.where(project_id: @project.self_and_descendants.pluck(:id)).pluck(:id).sort
    assert_equal ids, with_subprojects.candidate_issues.pluck(:id).sort

    global = build_rule(project: nil)
    assert_equal Issue.open.pluck(:id).sort, global.candidate_issues.pluck(:id).sort
  end

  # --- permissions ----------------------------------------------------------

  def test_visibility_and_editability
    rule = build_rule
    assert rule.save
    manager = User.find(2)   # Manager on ecookbook (role 1 has manage permission)
    developer = User.find(3) # Developer on ecookbook
    admin = User.find(1)

    assert rule.visible?(manager)
    assert rule.editable?(manager)
    assert rule.visible?(admin)
    assert rule.editable?(admin)
    assert_not rule.editable?(developer)
    assert_not rule.visible?(developer)

    Role.find(2).add_permission!(:view_automation_rules)
    developer = User.find(3) # fresh instance: roles are memoized per user object
    assert rule.visible?(developer)
    assert_not rule.editable?(developer)

    assert_not rule.visible?(User.anonymous)
    assert_not rule.editable?(User.anonymous)
  end

  def test_global_rules_are_admin_only
    rule = build_rule(project: nil)
    assert rule.save
    assert rule.visible?(User.find(1))
    assert rule.editable?(User.find(1))
    assert_not rule.visible?(User.find(2))
    assert_not rule.editable?(User.find(2))
  end

  # --- ordering ---------------------------------------------------------------

  def test_rules_are_positioned_per_project
    first = build_rule(name: 'first')
    second = build_rule(name: 'second')
    global = build_rule(name: 'global', project: nil)
    [first, second, global].each { |r| assert r.save }
    assert_equal 1, first.position
    assert_equal 2, second.position
    assert_equal 1, global.position

    second.position = 1
    assert second.save
    assert_equal %w[second first], @project.automation_rules.sorted.map(&:name)
  end

  def test_project_destroy_removes_its_rules
    project = Project.generate!
    rule = build_rule(project: project)
    assert rule.save
    project.destroy
    assert_nil AutomationRule.find_by(id: rule.id)
  end

  # --- sentence ---------------------------------------------------------------

  def test_sentence_describes_trigger_conditions_and_actions
    rule = build_rule(trigger_type: 'issue_closed',
                      conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }],
                      actions: [{ 'type' => 'set_status', 'value' => '5' },
                                { 'type' => 'add_note', 'text' => 'Done!' }])
    assert_equal 'When an issue is closed, if tracker is Bug, then set status to Closed and add note "Done!"',
                 rule.sentence
  end

  def test_sentence_without_conditions_or_actions
    rule = build_rule(trigger_type: 'issue_created')
    assert_equal 'When an issue is created, do nothing', rule.sentence
  end

  def test_update_trigger_sentences
    assert_equal 'When an issue is updated', build_rule(trigger_type: 'issue_updated').trigger_sentence
    assert_equal 'When status changes to Closed',
                 build_rule(trigger_type: 'issue_updated',
                            trigger_options: { 'change' => 'status_to',
                                               'status_id' => '5' }).trigger_sentence
    assert_equal 'When Due date changes',
                 build_rule(trigger_type: 'issue_updated',
                            trigger_options: { 'change' => 'field',
                                               'field' => 'due_date' }).trigger_sentence
    assert_equal 'When a note is added',
                 build_rule(trigger_type: 'issue_updated', trigger_options: { 'change' => 'note' }).trigger_sentence
  end

  def test_scheduled_trigger_sentence
    rule = build_rule(trigger_type: 'scheduled',
                      trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day',
                                         'time_of_day' => '09:00' })
    assert_equal 'Every day at 09:00, for open issues', rule.trigger_sentence
    rule.trigger_options = { 'interval_number' => '3', 'interval_unit' => 'hour', 'time_of_day' => '09:00' }
    assert_equal 'Every 3 hours, for open issues', rule.trigger_sentence
  end

  # --- scheduling ---------------------------------------------------------------

  def test_next_run_for_interval_rules_is_one_interval_after_the_last_run
    rule = build_rule(trigger_type: 'scheduled',
                      trigger_options: { 'interval_number' => '2', 'interval_unit' => 'hour' })
    now = Time.zone.parse('2026-03-10 10:00:00')
    assert_equal now + 2.hours, rule.compute_next_run(now)

    rule.last_run_at = now - 30.minutes
    assert_equal now + 90.minutes, rule.compute_next_run(now)
  end

  def test_next_run_for_time_of_day_rules_is_the_next_occurrence
    rule = build_rule(trigger_type: 'scheduled',
                      trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day',
                                         'time_of_day' => '09:00' })
    @author.pref.time_zone = 'UTC'

    before = Time.utc(2026, 3, 10, 8, 0)
    assert_equal Time.utc(2026, 3, 10, 9, 0), rule.compute_next_run(before)

    after = Time.utc(2026, 3, 10, 9, 30)
    assert_equal Time.utc(2026, 3, 11, 9, 0), rule.compute_next_run(after)

    rule.trigger_options = rule.trigger_options.merge('interval_unit' => 'week')
    assert_equal Time.utc(2026, 3, 17, 9, 0), rule.compute_next_run(after)
  end

  def test_time_of_day_uses_the_author_time_zone
    rule = build_rule(trigger_type: 'scheduled',
                      trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day',
                                         'time_of_day' => '09:00' })
    @author.pref.time_zone = 'Buenos Aires' # UTC-3
    @author.pref.save!
    rule.author = User.find(@author.id)
    assert_equal Time.utc(2026, 3, 10, 12, 0), rule.compute_next_run(Time.utc(2026, 3, 10, 8, 0))
  end

  def test_next_run_at_is_persisted_and_cleared_for_event_rules
    rule = build_rule(trigger_type: 'scheduled',
                      trigger_options: { 'interval_number' => '1', 'interval_unit' => 'hour' })
    assert rule.save
    assert_not_nil rule.next_run_at
    assert_not rule.due?(Time.current)
    assert rule.due?(rule.next_run_at + 1.second)

    rule.trigger_type = 'issue_created'
    assert rule.save
    assert_nil rule.next_run_at
    assert_not rule.due?
  end

  def test_record_run_updates_counters_and_error
    rule = build_rule
    assert rule.save
    rule.record_run!
    assert_equal 1, rule.runs_count
    assert_not_nil rule.last_run_at
    assert_nil rule.last_error

    rule.record_run!('boom')
    assert_equal 1, rule.runs_count
    assert_equal 'boom', rule.reload.last_error

    rule.record_run!
    assert_nil rule.reload.last_error
    assert_equal 2, rule.runs_count
  end

  def test_copy_from_duplicates_definition_but_not_runtime_state
    source = build_rule(name: 'Source', conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }],
                        actions: [{ 'type' => 'add_note', 'text' => 'x' }], runs_count: 5, last_error: 'old')
    assert source.save
    copy = AutomationRule.new(project: @project, author: User.find(1)).copy_from(source)
    assert_equal 'Source (copy)', copy.name
    assert_equal source.conditions, copy.conditions
    assert_equal source.actions, copy.actions
    assert_equal 0, copy.runs_count
    assert_nil copy.last_error
    assert_equal source.author_id, copy.author_id
    assert copy.save, copy.errors.full_messages.to_sentence
  end
end
