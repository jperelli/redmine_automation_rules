require "#{File.dirname(__FILE__)}/../test_helper"

# REST API (JSON + XML) for project rules.
class AutomationRulesApiTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :journals, :journal_details, :workflows

  def setup
    super
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'automation_rules')
    Role.find(1).add_permission!(:manage_automation_rules) # Manager: jsmith on ecookbook
  end

  def create_rule(attributes = {})
    AutomationRule.create!({ project: @project, author: User.find(2), name: 'Close bugs', trigger_type: 'issue_closed',
                             conditions: [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }],
                             actions: [{ 'type' => 'add_note', 'text' => 'Closed by rule' }] }.merge(attributes))
  end

  # --- index / show ---------------------------------------------------------------

  def test_index_json
    rule = create_rule
    create_rule(project: Project.find(2), name: 'Other project')

    get '/projects/ecookbook/automation_rules.json', headers: api_headers
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['automation_rules'].size
    r = json['automation_rules'].first
    assert_equal rule.id, r['id']
    assert_equal 'Close bugs', r['name']
    assert_equal({ 'id' => 1, 'name' => 'eCookbook' }, r['project'])
    assert_equal({ 'id' => 2, 'name' => 'John Smith' }, r['author'])
    assert_equal 'issue_closed', r['trigger_type']
    assert_equal true, r['active']
    assert_equal [{ 'type' => 'tracker', 'operator' => 'is', 'value' => '1' }], r['conditions']
    assert_equal [{ 'type' => 'add_note', 'text' => 'Closed by rule' }], r['actions']
    assert_match(/When an issue is closed/, r['sentence'])
    assert_equal 0, r['runs_count']
    assert_nil r['last_run_at']
  end

  def test_index_xml
    create_rule
    get '/projects/ecookbook/automation_rules.xml', headers: api_headers
    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'automation_rules[type=array] automation_rule' do
      assert_select 'name', text: 'Close bugs'
      assert_select 'trigger_type', text: 'issue_closed'
      assert_select 'conditions[type=array] condition type', text: 'tracker'
      assert_select 'actions[type=array] action text', text: 'Closed by rule'
    end
  end

  def test_show_json
    rule = create_rule(trigger_type: 'issue_updated', trigger_options: { 'change' => 'status_to', 'status_id' => '5' })
    get "/projects/ecookbook/automation_rules/#{rule.id}.json", headers: api_headers
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)['automation_rule']
    assert_equal rule.id, json['id']
    assert_equal({ 'change' => 'status_to', 'status_id' => '5' }, json['trigger_options'])
  end

  def test_index_requires_permission
    Role.find(1).remove_permission!(:manage_automation_rules)
    get '/projects/ecookbook/automation_rules.json', headers: api_headers
    assert_response :forbidden
  end

  def test_index_requires_authentication
    get '/projects/ecookbook/automation_rules.json'
    assert_response :unauthorized
  end

  # --- create / update / destroy ---------------------------------------------------

  def test_create_json
    payload = {
      automation_rule: {
        name: 'API rule', trigger_type: 'issue_created',
        conditions: [{ type: 'status', operator: 'is_open' }],
        actions: [{ type: 'set_status', value: '2' }, { type: 'add_note', text: 'Hi' }]
      }
    }
    assert_difference 'AutomationRule.count' do
      post '/projects/ecookbook/automation_rules.json', params: payload.to_json, headers: json_headers
    end
    assert_response :created
    rule = AutomationRule.order(:id).last
    assert_equal "http://www.example.com/projects/ecookbook/automation_rules/#{rule.id}", response.headers['Location']
    json = ActiveSupport::JSON.decode(response.body)['automation_rule']
    assert_equal rule.id, json['id']
    assert_equal 'API rule', rule.name
    assert_equal @project, rule.project
    assert_equal User.find(2), rule.author
    assert_equal [{ 'type' => 'status', 'operator' => 'is_open' }], rule.conditions
    assert_equal(%w[set_status add_note], rule.actions.map { |a| a['type'] })
  end

  def test_create_xml
    xml = <<~XML
      <automation_rule>
        <name>XML rule</name>
        <trigger_type>issue_created</trigger_type>
        <actions type="array">
          <action><type>add_note</type><text>From XML</text></action>
        </actions>
      </automation_rule>
    XML
    assert_difference 'AutomationRule.count' do
      post '/projects/ecookbook/automation_rules.xml', params: xml,
                                                       headers: api_headers.merge('CONTENT_TYPE' => 'application/xml')
    end
    assert_response :created
    rule = AutomationRule.order(:id).last
    assert_equal 'XML rule', rule.name
    assert_equal [{ 'type' => 'add_note', 'text' => 'From XML' }], rule.actions
  end

  def test_create_with_errors_json
    payload = { automation_rule: { name: '', trigger_type: 'issue_created', actions: [{ type: 'bogus' }] } }
    assert_no_difference 'AutomationRule.count' do
      post '/projects/ecookbook/automation_rules.json', params: payload.to_json, headers: json_headers
    end
    assert_response 422
    errors = ActiveSupport::JSON.decode(response.body)['errors']
    assert errors.any? { |e| e.include?('Name') }, errors.inspect
    assert errors.any? { |e| e.include?("unknown type 'bogus'") }, errors.inspect
  end

  def test_update_json_only_changes_the_given_attributes
    rule = create_rule
    put "/projects/ecookbook/automation_rules/#{rule.id}.json",
        params: { automation_rule: { name: 'Renamed', active: false } }.to_json, headers: json_headers
    assert_response :no_content
    rule.reload
    assert_equal 'Renamed', rule.name
    assert_not rule.active
    assert_equal 1, rule.conditions.size
    assert_equal 1, rule.actions.size
  end

  def test_update_can_clear_rows
    rule = create_rule
    put "/projects/ecookbook/automation_rules/#{rule.id}.json", params: { automation_rule: { conditions: [] } }.to_json,
                                                                headers: json_headers
    assert_response :no_content
    assert_equal [], rule.reload.conditions
  end

  def test_update_with_errors_json
    rule = create_rule
    put "/projects/ecookbook/automation_rules/#{rule.id}.json",
        params: { automation_rule: { trigger_type: 'nope' } }.to_json, headers: json_headers
    assert_response 422
    assert_equal 'issue_closed', rule.reload.trigger_type
  end

  def test_destroy_json
    rule = create_rule
    assert_difference 'AutomationRule.count', -1 do
      delete "/projects/ecookbook/automation_rules/#{rule.id}.json", headers: api_headers
    end
    assert_response :no_content
  end

  def test_write_requires_manage_permission
    rule = create_rule
    Role.find(2).add_permission!(:view_automation_rules) # Developer: dlopper
    dlopper = User.find(3)

    get "/projects/ecookbook/automation_rules/#{rule.id}.json", headers: api_headers(dlopper)
    assert_response :success

    put "/projects/ecookbook/automation_rules/#{rule.id}.json", params: { automation_rule: { name: 'x' } }.to_json,
                                                                headers: json_headers(dlopper)
    assert_response :forbidden
    delete "/projects/ecookbook/automation_rules/#{rule.id}.json", headers: api_headers(dlopper)
    assert_response :forbidden
    assert_equal 'Close bugs', rule.reload.name
  end

  # --- run_now / test -----------------------------------------------------------------

  def test_run_now_json
    rule = create_rule
    assert_difference 'Journal.count' do
      post "/projects/ecookbook/automation_rules/#{rule.id}/run_now.json", params: { issue_id: 1 }, headers: api_headers
    end
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)['run']
    assert_equal rule.id, json['rule_id']
    assert_equal 1, json['evaluated']
    assert_equal 1, json['matched']
    assert_equal 0, json['errors']
    result = json['results'].first
    assert_equal 1, result['issue_id']
    assert_equal true, result['matched']
    assert_equal ['add note "Closed by rule"'], result['actions']
    assert_equal 1, rule.reload.runs_count
  end

  def test_test_json_is_a_dry_run
    rule = create_rule
    assert_no_difference 'Journal.count' do
      post "/projects/ecookbook/automation_rules/#{rule.id}/test.json", params: { issue_id: 1 }, headers: api_headers
    end
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)['result']
    assert_equal true, json['dry_run']
    assert_equal true, json['matched']
    assert_equal [{ 'description' => 'tracker is Bug', 'matched' => true }], json['conditions']
    assert_match(/^Closed by rule/, json['notes'])
    assert_equal 0, rule.reload.runs_count
  end

  def test_test_json_with_non_matching_issue
    rule = create_rule
    post "/projects/ecookbook/automation_rules/#{rule.id}/test.json", params: { issue_id: 2 }, headers: api_headers
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)['result']
    assert_equal false, json['matched']
    assert_equal [], json['actions']
  end

  def test_test_json_requires_an_issue
    rule = create_rule
    post "/projects/ecookbook/automation_rules/#{rule.id}/test.json", headers: api_headers
    assert_response :bad_request
  end

  def test_test_xml
    rule = create_rule
    post "/projects/ecookbook/automation_rules/#{rule.id}/test.xml", params: { issue_id: 1 }, headers: api_headers
    assert_response :success
    assert_select 'result' do
      assert_select 'matched', text: 'true'
      assert_select 'conditions[type=array] condition description', text: 'tracker is Bug'
    end
  end

  private

  def api_headers(user = User.find(2))
    { 'X-Redmine-API-Key' => user.api_key }
  end

  def json_headers(user = User.find(2))
    api_headers(user).merge('CONTENT_TYPE' => 'application/json')
  end
end
