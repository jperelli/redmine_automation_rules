class AutomationRulesController < ApplicationController
  before_action :find_rule_project
  before_action :authorize_rules
  before_action :find_rule, only: %i[show edit update destroy copy toggle run_now test]
  before_action :require_manage, only: %i[new create edit update destroy copy toggle run_now]

  accept_api_auth :index, :show, :create, :update, :destroy, :run_now, :test

  EXECUTIONS_SHOWN = 50

  helper :automation_rules
  helper :issues
  helper :custom_fields

  def index
    @rules = rules_scope.sorted.to_a
    @inherited_rules = if @project
                         AutomationRule.applicable_to(@project).sorted.reject do |rule|
                           rule.project_id == @project.id
                         end.select(&:visible?)
                       else
                         []
                       end
    respond_to do |format|
      format.html
      format.api
    end
  end

  def show
    @executions = @rule.executions.recent.includes(:issue).limit(EXECUTIONS_SHOWN).to_a
    respond_to do |format|
      format.html
      format.api
    end
  end

  def new
    @rule = rules_scope.new(trigger_type: 'issue_created', author: User.current)
    return if params[:recipe].blank?

    @recipe = params[:recipe].to_s
    flash.now[:warning] = l(:automation_rules_error_unknown_recipe) unless @rule.apply_recipe(@recipe, User.current)
  end

  def create
    @rule = rules_scope.new(author: User.current)
    @rule.safe_attributes = rule_params
    if @rule.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_create)
          redirect_to rules_index_path
        end
        format.api { render action: 'show', status: :created, location: rule_url_for(@rule) }
      end
    else
      respond_to do |format|
        format.html { render action: 'new' }
        format.api { render_validation_errors(@rule) }
      end
    end
  end

  def edit; end

  def update
    @rule.safe_attributes = rule_params
    if @rule.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to rules_index_path
        end
        format.js { head :ok }
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.html { render action: 'edit' }
        format.js { head :unprocessable_entity }
        format.api { render_validation_errors(@rule) }
      end
    end
  end

  def destroy
    @rule.destroy
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_delete)
        redirect_to rules_index_path
      end
      format.api { render_api_ok }
    end
  end

  def copy
    copy = rules_scope.new(author: User.current).copy_from(@rule)
    if copy.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to polymorphic_path([:edit, @project, copy])
    else
      flash[:error] = copy.errors.full_messages.to_sentence
      redirect_to rules_index_path
    end
  end

  def toggle
    @rule.update(active: !@rule.active)
    redirect_back_or_default rules_index_path
  end

  # Runs the rule right now against the issues it applies to (scheduled rules)
  # or against one issue given by issue_id.
  def run_now
    issue = find_issue_param(required: !@rule.scheduled?)
    return if performed?

    results = if issue
                [RedmineAutomationRules::Runner.new(@rule, issue, trigger: 'manual').run]
              else
                @rule.candidate_issues.map { |candidate| RedmineAutomationRules::Runner.new(@rule, candidate, trigger: 'manual').run }
              end
    @results = results
    matched = results.count(&:matched?)
    errors = results.count { |r| r.error.present? }
    respond_to do |format|
      format.html do
        flash[errors.positive? ? :error : :notice] =
          l(:automation_rules_notice_run_now, matched: matched, evaluated: results.size, errors: errors)
        redirect_to polymorphic_path([@project, @rule])
      end
      format.api { render action: 'run_now' }
    end
  end

  # Dry run: shows which conditions match and what the actions would do,
  # without saving anything.
  def test
    @issue = find_issue_param(required: request.post? || api_request?)
    return if performed?

    @result = RedmineAutomationRules::Runner.new(@rule, @issue, trigger: 'test', dry_run: true).run if @issue
    respond_to do |format|
      format.html
      format.api { render action: 'test' }
    end
  end

  # Form schema (triggers, condition/action types and option lists) as JSON.
  def fields
    render json: RedmineAutomationRules::Schema.for_project(@project)
  end

  private

  def find_rule_project
    @project = Project.find(params[:project_id]) if params[:project_id].present?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_rules
    if @project
      authorize
    else
      require_admin
    end
  end

  def require_manage
    return true if @rule.nil? || @rule.editable?

    deny_access
  end

  def rules_scope
    @project ? @project.automation_rules : AutomationRule.global
  end

  def find_rule
    @rule = rules_scope.find(params[:id])
    render_403 unless @rule.visible?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # The HTML form has no input at all when every condition/action row was
  # removed, so a missing key means "none" there (the full form always carries
  # trigger_type; the reorder request and the API only change what they send).
  def rule_params
    raw = params[:automation_rule]
    attrs = raw.respond_to?(:to_unsafe_hash) ? raw.to_unsafe_hash : (raw || {}).to_h
    if !api_request? && attrs.key?('trigger_type')
      attrs['conditions'] ||= []
      attrs['actions'] ||= []
    end
    attrs
  end

  def rules_index_path
    polymorphic_path([@project, :automation_rules])
  end

  def rule_url_for(rule)
    polymorphic_url([@project, rule])
  end

  def find_issue_param(required:)
    id = params[:issue_id].to_s.delete_prefix('#')
    if id.blank?
      render_error(status: 400, message: l(:automation_rules_error_issue_required)) if required
      return nil
    end
    issue = Issue.visible.find_by(id: id)
    if issue.nil?
      render_error(status: 404, message: l(:automation_rules_error_issue_not_found, id: id))
      return nil
    end
    unless @rule.applies_to?(issue.project)
      render_error(status: 422, message: l(:automation_rules_error_issue_not_in_scope, id: id))
      return nil
    end
    issue
  end
end
