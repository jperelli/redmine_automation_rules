require "#{File.dirname(__FILE__)}/../test_helper"

class AutomationRulesControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :journals, :journal_details, :workflows

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['automation_rules']
    Role.find(1).add_permission!(:manage_automation_rules)
    @request.session[:user_id] = 2
  end

  def create_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: User.find(2), name: 'Close bugs', trigger_type: 'issue_closed',
                             conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }],
                             actions: [{ 'type' => 'add_note', 'text' => 'Closed by rule' }] }.merge(attributes))
  end

  # --- index ------------------------------------------------------------------

  def test_index
    rule = create_rule
    get :index, params: { project_id: @project.id }
    assert_response :success
    assert_select 'h2', text: I18n.t(:label_automation_rules)
    assert_select "tr#automation-rule-#{rule.id}" do
      assert_select 'td.name a', text: 'Close bugs'
      assert_select 'td.sentence', text: /When an issue is closed, if tracker is Bug/
      assert_select 'td.active .automation-rule-active'
    end
    assert_select 'a.icon-add', text: I18n.t(:automation_rules_new_rule)
    assert_select 'select.automation-rule-recipe-select[data-url=?]', '/projects/ecookbook/automation_rules/new' do
      assert_select 'option', count: RedmineAutomationRules::Recipes.keys.size + 1
      assert_select 'option[value=auto_close_resolved]', text: I18n.t(:automation_rules_recipe_auto_close_resolved)
    end
  end

  def test_index_shows_empty_message_and_inherited_rules
    global = AutomationRule.create!(project: nil, author: User.find(1), name: 'Global one',
                                    trigger_type: 'issue_created')
    subproject = Project.find(3)
    subproject.enabled_module_names = subproject.enabled_module_names | ['automation_rules']
    Member.create!(project: subproject, principal: User.find(2), role_ids: [1])
    get :index, params: { project_id: 3 }
    assert_response :success
    assert_select 'p.nodata', text: I18n.t(:label_no_automation_rules)
    # jsmith is not admin, so the global rule is not visible to him
    assert_select 'td.name', text: 'Global one', count: 0

    @request.session[:user_id] = 1
    get :index, params: { project_id: 3 }
    assert_select 'h3', text: I18n.t(:automation_rules_inherited_rules)
    assert_select "tr#automation-rule-#{global.id} td.name", text: 'Global one'
  end

  def test_index_requires_permission
    Role.find(1).remove_permission!(:manage_automation_rules)
    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  def test_index_with_view_permission_only_hides_management_links
    Role.find(1).remove_permission!(:manage_automation_rules)
    Role.find(1).add_permission!(:view_automation_rules)
    create_rule
    get :index, params: { project_id: @project.id }
    assert_response :success
    assert_select 'a.icon-add', count: 0
    assert_select 'a.icon-edit', count: 0
    assert_select 'a.icon-del', count: 0
  end

  def test_index_requires_module
    @project.enabled_module_names = @project.enabled_module_names - ['automation_rules']
    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  def test_project_menu_shows_automation_tab
    get :index, params: { project_id: @project.id }
    assert_select '#main-menu a.automation-rules', text: I18n.t(:label_automation_rules_menu)
  end

  # --- show -------------------------------------------------------------------

  def test_show
    rule = create_rule(last_error: 'Something failed')
    get :show, params: { project_id: @project.id, id: rule.id }
    assert_response :success
    assert_select 'h2', text: /Close bugs/
    assert_select 'p.automation-rule-sentence', text: /then add note/
    assert_select 'div.automation-rule-last-error', text: 'Something failed'
    assert_select 'a.icon-edit'
    assert_select 'div.automation-rule-executions p.nodata', text: I18n.t(:automation_rules_no_executions)
  end

  def test_show_lists_the_execution_log
    rule = create_rule
    (1..60).each do |i|
      AutomationRulesExecution.create!(automation_rule: rule, issue_id: 1, trigger: 'test', applied: "row #{i}",
                                       created_at: Time.current)
    end
    AutomationRulesExecution.create!(automation_rule: rule, issue: Issue.find(1), trigger: 'issue_closed',
                                     applied: "set status to Closed\nadd note \"Bye\"", created_at: 1.hour.ago)
    failed = AutomationRulesExecution.create!(automation_rule: rule, issue: Issue.find(2), trigger: 'manual',
                                              error: 'Status is invalid', created_at: Time.current)

    get :show, params: { project_id: @project.id, id: rule.id }
    assert_response :success
    assert_select 'table.automation-rule-executions-table tbody tr', count: AutomationRulesController::EXECUTIONS_SHOWN
    assert_select 'tr.automation-rule-execution-error' do
      assert_select 'td a[href=?]', "/issues/#{failed.issue_id}"
      assert_select 'td', text: I18n.t(:automation_rules_execution_trigger_manual)
      assert_select 'td span.automation-rule-error', text: 'Status is invalid'
    end
    assert_select 'tr.automation-rule-execution-ok ol li', text: 'set status to Closed'
    assert_select 'tr.automation-rule-execution-ok ol li', text: 'add note "Bye"'
    assert_select 'tr.automation-rule-execution-ok ol li', text: 'row 60'
    assert_select 'tr.automation-rule-execution-ok ol li', text: 'row 1', count: 0 # only the newest 50 are shown
  end

  def test_show_of_rule_from_another_project_is_not_found
    rule = create_rule(project: Project.find(2))
    get :show, params: { project_id: @project.id, id: rule.id }
    assert_response :not_found
  end

  # --- new / create --------------------------------------------------------------

  def test_new
    get :new, params: { project_id: @project.id }
    assert_response :success
    assert_select 'form#automation-rule-form' do
      assert_select 'select#automation_rule_trigger_type option', count: AutomationRule::TRIGGER_TYPES.size
      assert_select 'div.automation-rule-fields[data-fields-url=?]', '/projects/ecookbook/automation_rules/fields'
      assert_select 'div#automation-rule-conditions'
      assert_select 'div#automation-rule-actions'
    end
  end

  def test_new_from_recipe_prefills_the_form
    get :new, params: { project_id: @project.id, recipe: 'auto_close_resolved' }
    assert_response :success
    assert_select 'p.automation-rule-recipe-info', text: /Auto-close resolved issues after 14 days/
    assert_select 'input#automation_rule_name[value=?]', I18n.t(:automation_rules_recipe_auto_close_resolved)
    assert_select 'select#automation_rule_trigger_type option[selected][value=scheduled]'
    assert_select 'div.automation-rule-fields[data-conditions*=?]', 'updated_ago'
    assert_select 'div.automation-rule-fields[data-actions*=?]', 'close_issue'
  end

  def test_new_from_unknown_recipe_warns_and_shows_an_empty_form
    get :new, params: { project_id: @project.id, recipe: 'nope' }
    assert_response :success
    assert_select 'div.flash.warning', text: I18n.t(:automation_rules_error_unknown_recipe)
    assert_select 'p.automation-rule-recipe-info', count: 0
    assert_select 'select#automation_rule_trigger_type option[selected][value=issue_created]'
  end

  def test_new_requires_manage_permission
    Role.find(1).remove_permission!(:manage_automation_rules)
    Role.find(1).add_permission!(:view_automation_rules)
    get :new, params: { project_id: @project.id }
    assert_response :forbidden
  end

  def test_create
    assert_difference 'AutomationRule.count' do
      post :create, params: {
        project_id: @project.id,
        automation_rule: {
          name: 'New rule', description: 'desc', trigger_type: 'issue_updated', active: '1',
          trigger_options: { change: 'status_to', status_id: '5', field: '' },
          conditions: { '0' => { type: 'tracker', operator: 'is_not', value: '2' } },
          actions: { '0' => { type: 'add_note', text: 'Hello {{issue.subject}}', private: '0' },
                     '1' => { type: 'set_status', value: '2' } }
        }
      }
    end
    assert_redirected_to '/projects/ecookbook/automation_rules'
    rule = AutomationRule.order(:id).last
    assert_equal 'New rule', rule.name
    assert_equal @project, rule.project
    assert_equal User.find(2), rule.author
    assert_equal 'status_to', rule.trigger_option('change')
    assert_equal '5', rule.trigger_option('status_id')
    assert_equal [{ 'type' => 'tracker', 'operator' => 'is_not', 'value' => '2' }], rule.conditions
    assert_equal(%w[add_note set_status], rule.actions.map { |a| a['type'] })
    assert rule.active
  end

  def test_create_with_errors_renders_the_form
    assert_no_difference 'AutomationRule.count' do
      post :create, params: { project_id: @project.id,
                              automation_rule: { name: '', trigger_type: 'issue_created',
                                                 actions: { '0' => { type: 'add_note', text: '' } } } }
    end
    assert_response :success
    assert_select '#errorExplanation' do
      assert_select 'li', text: /Name/
      assert_select 'li', text: /Action 1/
    end
    # the submitted rows are kept for the JS to re-render
    assert_select 'div.automation-rule-fields[data-actions]'
  end

  def test_create_ignores_project_and_author_params
    post :create, params: { project_id: @project.id,
                            automation_rule: { name: 'Sneaky', trigger_type: 'issue_created', project_id: 2,
                                               author_id: 1 } }
    rule = AutomationRule.order(:id).last
    assert_equal 1, rule.project_id
    assert_equal 2, rule.author_id
  end

  # --- edit / update --------------------------------------------------------------

  def test_edit
    rule = create_rule
    get :edit, params: { project_id: @project.id, id: rule.id }
    assert_response :success
    assert_select 'input#automation_rule_name[value=?]', 'Close bugs'
    assert_select 'select#automation_rule_trigger_type option[selected][value=issue_closed]'
    assert_select 'div.automation-rule-fields[data-conditions]' do |elements|
      assert_equal rule.conditions, JSON.parse(elements.first['data-conditions'])
    end
  end

  def test_update
    rule = create_rule
    put :update, params: { project_id: @project.id, id: rule.id,
                           automation_rule: { name: 'Renamed', trigger_type: 'issue_closed', active: '0' } }
    assert_redirected_to '/projects/ecookbook/automation_rules'
    rule.reload
    assert_equal 'Renamed', rule.name
    assert_not rule.active
    # a full form submission without rows clears the rows
    assert_equal [], rule.conditions
    assert_equal [], rule.actions
  end

  def test_update_position_via_js_keeps_rows
    first = create_rule(name: 'first')
    second = create_rule(name: 'second')
    put :update, params: { project_id: @project.id, id: second.id, automation_rule: { position: 1 } }, xhr: true
    assert_response :ok
    assert_equal %w[second first], @project.automation_rules.sorted.map(&:name)
    assert_equal 1, second.reload.conditions.size
    assert_equal 2, first.reload.position
  end

  def test_update_with_errors
    rule = create_rule
    put :update, params: { project_id: @project.id, id: rule.id, automation_rule: { name: '' } }
    assert_response :success
    assert_select '#errorExplanation'
    assert_equal 'Close bugs', rule.reload.name
  end

  def test_update_denied_without_manage_permission
    rule = create_rule
    Role.find(1).remove_permission!(:manage_automation_rules)
    Role.find(1).add_permission!(:view_automation_rules)
    put :update, params: { project_id: @project.id, id: rule.id, automation_rule: { name: 'x' } }
    assert_response :forbidden
  end

  # --- destroy / copy / toggle ---------------------------------------------------

  def test_destroy
    rule = create_rule
    assert_difference 'AutomationRule.count', -1 do
      delete :destroy, params: { project_id: @project.id, id: rule.id }
    end
    assert_redirected_to '/projects/ecookbook/automation_rules'
  end

  def test_copy
    rule = create_rule
    assert_difference 'AutomationRule.count' do
      post :copy, params: { project_id: @project.id, id: rule.id }
    end
    copy = AutomationRule.order(:id).last
    assert_redirected_to "/projects/ecookbook/automation_rules/#{copy.id}/edit"
    assert_equal 'Close bugs (copy)', copy.name
    assert_equal rule.conditions, copy.conditions
    assert_equal rule.actions, copy.actions
    assert_equal @project, copy.project
  end

  def test_toggle
    rule = create_rule
    post :toggle, params: { project_id: @project.id, id: rule.id }
    assert_redirected_to '/projects/ecookbook/automation_rules'
    assert_not rule.reload.active
    post :toggle, params: { project_id: @project.id, id: rule.id }
    assert rule.reload.active
  end

  # --- test (dry run) --------------------------------------------------------------

  def test_test_form
    rule = create_rule
    get :test, params: { project_id: @project.id, id: rule.id }
    assert_response :success
    assert_select 'form.automation-rule-test-form input#test_issue_id'
    assert_select 'div.automation-rule-test-result', count: 0
  end

  def test_test_on_matching_issue_shows_result_without_saving
    rule = create_rule
    assert_no_difference 'Journal.count' do
      get :test, params: { project_id: @project.id, id: rule.id, issue_id: '#1' }
    end
    assert_response :success
    assert_select 'div.automation-rule-test-result' do
      assert_select 'li.matched', text: /tracker is Bug/
      assert_select 'p.automation-rule-verdict.matched'
      assert_select 'ol.automation-rule-rows li', text: /add note/
      assert_select 'li', text: /Closed by rule/
    end
    assert_select 'form.automation-rule-run-on-issue[action=?]',
                  "/projects/ecookbook/automation_rules/#{rule.id}/run_now" do
      assert_select 'input[name=issue_id][value="1"]'
    end
    assert_equal 0, rule.reload.runs_count
  end

  def test_test_result_offers_no_real_run_to_viewers
    rule = create_rule
    Role.find(2).add_permission!(:view_automation_rules)
    @request.session[:user_id] = 3
    get :test, params: { project_id: @project.id, id: rule.id, issue_id: 1 }
    assert_response :success
    assert_select 'p.automation-rule-verdict.matched'
    assert_select 'form.automation-rule-run-on-issue', count: 0
  end

  def test_test_on_non_matching_issue
    rule = create_rule
    get :test, params: { project_id: @project.id, id: rule.id, issue_id: 2 } # Feature
    assert_response :success
    assert_select 'li.not-matched', text: /tracker is Bug/
    assert_select 'p.automation-rule-verdict.not-matched'
    assert_select 'form.automation-rule-run-on-issue', count: 0
  end

  def test_test_with_issue_outside_scope
    rule = create_rule
    get :test, params: { project_id: @project.id, id: rule.id, issue_id: 4 } # onlinestore
    assert_response 422
  end

  def test_test_with_unknown_issue
    rule = create_rule
    get :test, params: { project_id: @project.id, id: rule.id, issue_id: 99_999 }
    assert_response :not_found
  end

  # --- run_now ------------------------------------------------------------------

  def test_run_now_on_one_issue
    rule = create_rule
    assert_difference 'Journal.count' do
      post :run_now, params: { project_id: @project.id, id: rule.id, issue_id: 1 }
    end
    assert_redirected_to "/projects/ecookbook/automation_rules/#{rule.id}"
    assert_match(/1 matched, 0 errors/, flash[:notice])
    assert_equal 1, rule.reload.runs_count
  end

  def test_run_now_on_event_rule_requires_an_issue
    rule = create_rule
    post :run_now, params: { project_id: @project.id, id: rule.id }
    assert_response :bad_request
  end

  def test_run_now_on_scheduled_rule_evaluates_candidates
    rule = create_rule(trigger_type: 'scheduled',
                       trigger_options: { 'interval_number' => '1', 'interval_unit' => 'day' })
    post :run_now, params: { project_id: @project.id, id: rule.id }
    assert_redirected_to "/projects/ecookbook/automation_rules/#{rule.id}"
    bugs = rule.candidate_issues.where(tracker_id: 1).count
    assert_match(/#{rule.candidate_issues.count} issues: #{bugs} matched/, flash[:notice])
  end

  # --- fields -------------------------------------------------------------------

  def test_fields_returns_the_form_schema
    get :fields, params: { project_id: @project.id }
    assert_response :success
    schema = JSON.parse(response.body)
    assert_equal AutomationRule::TRIGGER_TYPES, schema['triggers'].map(&:last)
    assert_includes schema['conditions'].map { |c| c['key'] }, 'tracker'
    assert_includes schema['actions'].map { |a| a['key'] }, 'add_note'
    assert_equal @project.trackers.map { |t| [t.name, t.id.to_s] }, schema['options']['tracker']
    assert schema['options']['status'].any?
    assert schema['labels']['button_delete'].present?
  end

  # --- global rules --------------------------------------------------------------

  def test_global_rules_require_admin
    get :index
    assert_response :forbidden

    @request.session[:user_id] = 1
    get :index
    assert_response :success
    assert_select 'h2', text: I18n.t(:automation_rules_global_rules)
  end

  def test_admin_creates_a_global_rule
    @request.session[:user_id] = 1
    assert_difference 'AutomationRule.global.count' do
      post :create, params: { automation_rule: { name: 'Everywhere', trigger_type: 'issue_created' } }
    end
    assert_redirected_to '/automation_rules'
    rule = AutomationRule.order(:id).last
    assert_nil rule.project_id
    assert_equal 1, rule.author_id
  end
end
