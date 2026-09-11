class AutomationRulesAdminController < ApplicationController
  layout 'admin'
  before_action :require_admin

  def index
    @rules = []
  end
end
