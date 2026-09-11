module RedmineAutomationRules
  module ProjectPatch
    def self.included(base)
      base.class_eval do
        has_many :automation_rules, dependent: :destroy
      end
    end
  end
end
