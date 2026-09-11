class AutomationRulesAdminController < ApplicationController
  layout 'admin'
  before_action :require_admin

  helper :automation_rules

  def index
    @global_rules = AutomationRule.global.sorted.to_a
    @project_rules = AutomationRule.where.not(project_id: nil).includes(:project, :author).sorted.to_a
                                   .sort_by { |rule| [rule.project.lft, rule.position.to_i, rule.id] }
  end
end
