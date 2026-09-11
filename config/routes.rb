resources :projects do
  resources :automation_rules, only: [:index]
end

get 'admin/automation_rules', to: 'automation_rules_admin#index', as: 'admin_automation_rules'
