module RedmineAutomationRules
  VERSION = '0.1.0'.freeze

  def self.setting(name)
    Setting.plugin_automation_rules[name]
  end

  # Prepends the model patches. Called from init.rb; idempotent so reloading
  # in development does not stack the patches.
  def self.apply_patches
    Project.include(ProjectPatch) unless Project.include?(ProjectPatch)
    Issue.prepend(IssuePatch) unless Issue.include?(IssuePatch)
    TimeEntry.prepend(TimeEntryPatch) unless TimeEntry.include?(TimeEntryPatch)
  end
end

require_relative 'redmine_automation_rules/hooks'
require_relative 'redmine_automation_rules/definition'
require_relative 'redmine_automation_rules/date_macros'
require_relative 'redmine_automation_rules/working_days'
require_relative 'redmine_automation_rules/substitution'
require_relative 'redmine_automation_rules/webhook'
require_relative 'redmine_automation_rules/conditions'
require_relative 'redmine_automation_rules/actions'
require_relative 'redmine_automation_rules/schema'
require_relative 'redmine_automation_rules/runner'
require_relative 'redmine_automation_rules/events'
require_relative 'redmine_automation_rules/project_patch'
