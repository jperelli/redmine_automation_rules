module RedmineAutomationRules
  # Cron-less scheduling: runs AutomationRulesChecker from ordinary web
  # requests (WP-Cron style) when the plugin setting +scheduler_mode+ is "web".
  # Adapted from Redmine Periodic Task.
  #
  # Every request calls +maybe_run!+. A per-process timestamp keeps most calls
  # free of any DB access; when the interval has elapsed the process tries to
  # claim AutomationRulesSchedulerLock so that only one process runs the
  # checker, then runs it in a background thread so the response is not delayed.
  module WebScheduler
    MODES = %w[cron web].freeze
    DEFAULT_INTERVAL_MINUTES = 5

    class << self
      # Run the checker inline instead of in a thread (tests).
      attr_accessor :synchronous

      def settings
        Setting.plugin_automation_rules || {}
      end

      def mode
        MODES.include?(settings['scheduler_mode'].to_s) ? settings['scheduler_mode'].to_s : 'cron'
      end

      def enabled?
        mode == 'web'
      end

      def interval
        minutes = settings['web_check_interval'].to_i
        minutes = DEFAULT_INTERVAL_MINUTES if minutes <= 0
        minutes.minutes
      end

      def maybe_run!
        return false unless enabled?

        now = Time.current
        return false if @next_check_at && now < @next_check_at

        @next_check_at = now + interval
        return false unless AutomationRulesSchedulerLock.claim?(interval, now)

        run
        true
      rescue StandardError => e
        Rails.logger.error "[automation_rules] WebScheduler: #{e.class}: #{e.message}"
        false
      end

      def reset!
        @next_check_at = nil
      end

      private

      def run
        if synchronous
          AutomationRulesChecker.check!(source: 'web')
        else
          Thread.new do
            Rails.application.executor.wrap do
              AutomationRulesChecker.check!(source: 'web')
            rescue StandardError => e
              Rails.logger.error "[automation_rules] WebScheduler: #{e.class}: #{e.message}"
            end
          end
        end
      end
    end
  end

  # Prepended to ApplicationController so every request can trigger the scheduler.
  module WebSchedulerControllerPatch
    def self.prepended(base)
      base.after_action :automation_rules_maybe_run_scheduler
    end

    private

    def automation_rules_maybe_run_scheduler
      WebScheduler.maybe_run!
    end
  end
end
