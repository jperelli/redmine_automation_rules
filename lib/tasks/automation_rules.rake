desc <<~END_DESC
  Evaluate the due scheduled automation rules

  Example:
    rake redmine:check_automation_rules RAILS_ENV="production"
END_DESC

Rails.configuration.active_job.queue_adapter = :inline if Rails.configuration.respond_to?(:active_job)

namespace :redmine do
  task check_automation_rules: :environment do
    AutomationRulesChecker.check!
  end
end
