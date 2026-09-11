module RedmineAutomationRules
  VERSION = '0.1.0'.freeze

  def self.setting(name)
    Setting.plugin_automation_rules[name]
  end
end

require_relative 'redmine_automation_rules/hooks'
