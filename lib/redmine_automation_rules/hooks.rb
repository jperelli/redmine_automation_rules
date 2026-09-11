module RedmineAutomationRules
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      stylesheet_link_tag('automation_rules', plugin: 'automation_rules') +
        javascript_include_tag('automation_rules', plugin: 'automation_rules')
    end

    # Lists the rules that ran on the issue being viewed. The sidebar partial
    # is shared with the issue list, where @issue is not set and nothing renders.
    render_on :view_issues_sidebar_issues_bottom, partial: 'automation_rules/issue_sidebar'
  end
end
