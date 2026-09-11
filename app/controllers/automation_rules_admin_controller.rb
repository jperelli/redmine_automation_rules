class AutomationRulesAdminController < ApplicationController
  layout 'admin'
  before_action :require_admin

  helper :automation_rules

  def index
    @global_rules = AutomationRule.global.sorted.to_a
    @project_rules = AutomationRule.where.not(project_id: nil).includes(:project, :author).sorted.to_a
                                   .sort_by { |rule| [rule.project.lft, rule.position.to_i, rule.id] }
  end

  # Runs the scheduled rules checker without waiting for cron or calling the
  # check URL, to verify a scheduler setup.
  def run_checker
    count = AutomationRulesChecker.check!(source: 'manual')
    flash[:notice] = l(:notice_automation_rules_checker_run, count: count)
    redirect_to plugin_settings_path('automation_rules')
  end
end
