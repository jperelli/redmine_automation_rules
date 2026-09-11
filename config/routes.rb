# Cron-less trigger for external schedulers, protected by Redmine's sys API key.
# Declared before the global rules resource so /automation_rules/check is not
# taken for a rule id.
match 'automation_rules/check', to: 'automation_rules_sys#check', as: 'automation_rules_check', via: %i[get post]

automation_rule_actions = lambda do
  member do
    post :copy
    post :toggle
    post :run_now
    match :test, via: %i[get post]
  end
  collection do
    get :fields
  end
end

# Project rules: /projects/:project_id/automation_rules
resources :projects do
  resources :automation_rules, &automation_rule_actions
end

# Global rules (admin only): /automation_rules
resources :automation_rules, &automation_rule_actions

get 'admin/automation_rules', to: 'automation_rules_admin#index', as: 'admin_automation_rules'
post 'admin/automation_rules/run_checker', to: 'automation_rules_admin#run_checker',
                                           as: 'automation_rules_run_checker'
