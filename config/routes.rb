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
