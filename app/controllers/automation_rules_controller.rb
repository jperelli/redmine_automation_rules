class AutomationRulesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  accept_api_auth :index

  def index
    @rules = []
    respond_to do |format|
      format.html
      format.api
    end
  end
end
