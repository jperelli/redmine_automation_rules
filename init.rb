require 'redmine'

# Redmine loads plugin init.rb files inside a to_prepare block, so requiring
# the patches here and prepending them right away is the whole boot sequence.
require_relative 'lib/redmine_automation_rules'

Redmine::Plugin.register :automation_rules do
  name 'Automation Rules'
  author 'Julian Perelli'
  description 'No-code automation rules for Redmine issues: when X happens, if Y, then do Z.'
  version '0.1.0'
  url 'https://github.com/jperelli/redmine_automation_rules'
  author_url 'https://jperelli.com.ar/'
  requires_redmine version_or_higher: '5.1.0'

  settings default: {
    'scheduler_mode' => 'cron',
    'web_check_interval' => '5',
    'run_actions_async' => '0'
  }, partial: 'settings/automation_rules'

  project_module :automation_rules do
    permission :manage_automation_rules,
               { automation_rules: %i[index show new create edit update destroy copy toggle move run_now test fields] },
               require: :member
    permission :view_automation_rules,
               { automation_rules: %i[index show test fields] },
               read: true
  end

  menu :project_menu, :automation_rules,
       { controller: 'automation_rules', action: 'index' },
       caption: :label_automation_rules_menu, after: :settings, param: :project_id

  menu :admin_menu, :automation_rules,
       { controller: 'automation_rules_admin', action: 'index' },
       caption: :label_automation_rules, html: { class: 'icon icon-workflows' }
end
