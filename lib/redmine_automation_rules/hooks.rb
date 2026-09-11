module RedmineAutomationRules
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      stylesheet_link_tag('automation_rules', plugin: 'automation_rules') +
        javascript_include_tag('automation_rules', plugin: 'automation_rules')
    end
  end
end
