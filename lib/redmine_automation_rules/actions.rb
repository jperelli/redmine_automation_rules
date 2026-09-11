module RedmineAutomationRules
  class ActionError < StandardError; end

  # Registry of action types. Each type is one class under
  # lib/redmine_automation_rules/actions/. An action changes the issue in
  # memory in #apply (the runner saves once, with a single journal, after all
  # actions ran) and/or does side effects in #perform, which runs after the
  # issue was saved (emails, webhooks, creating other issues).
  module Actions
    def self.registry
      @registry ||= {}
    end

    def self.register(klass)
      registry[klass.key] = klass
    end

    def self.all
      registry.values
    end

    def self.[](key)
      registry[key.to_s]
    end

    def self.build(row)
      return nil unless row.is_a?(Hash)

      klass = registry[row['type'].to_s]
      klass&.new(row)
    end

    def self.schema(project = nil)
      all.map { |klass| klass.schema(project) }
    end

    class Base
      include Definition

      def self.i18n_prefix
        'automation_rules_action'
      end

      def self.inherited(subclass)
        super
        Actions.register(subclass)
      end

      # Variants of the action offered as the first select of the row, like
      # the operator of a condition.
      def self.modes(*names)
        if names.empty?
          @modes || []
        else
          @modes = names.map(&:to_s)
          param 'mode', widget: 'select', options: @modes.map { |mode| [:"automation_rules_mode_#{mode}", mode] }
        end
      end

      # Change +issue+ in memory. +context+ is the execution context (see Runner).
      def apply(issue, context); end

      # Side effects after the issue was saved. Not called on dry runs.
      def perform(issue, context); end

      # Changes the issue, so the runner has to save it after #apply.
      def modifies_issue?
        true
      end

      def mode
        value = param('mode').to_s
        self.class.modes.include?(value) ? value : self.class.modes.first
      end

      def mode_label
        l("automation_rules_mode_#{mode}")
      end

      # "set status to Closed"
      def describe
        label.downcase
      end

      def validate
        errors = super
        errors << l(:automation_rules_error_invalid_url) if param?('url') && !Webhook.valid_url?(param('url'))
        errors
      end

      private

      def fail!(message)
        raise ActionError, message
      end

      def rule(context)
        context[:rule]
      end

      def author(context)
        context[:user] || rule(context)&.author || User.current
      end

      # The user who caused the event, falling back to the rule author.
      def actor(context)
        context[:actor].presence || author(context)
      end

      def substitute(text, issue, context)
        Substitution.apply(text.to_s, issue, context)
      end

      def find_user(id)
        ::User.active.find_by(id: id)
      end

      # Users a "who" parameter resolves to: a specific user, the author, the
      # assignee, the acting user, members of a role or of a group.
      def resolve_users(who, issue, context, user_id: param('user_id'), role_id: param('role_id'),
                        group_id: param('group_id'))
        case who.to_s
        when 'user' then [find_user(user_id)].compact
        when 'author' then [issue.author].compact
        when 'assignee' then issue.assigned_to.is_a?(::User) ? [issue.assigned_to] : []
        when 'current_user' then [actor(context)].select(&:logged?)
        when 'role' then users_with_role(issue.project, role_id)
        when 'group' then group_users(group_id)
        else []
        end
      end

      def group_users(group_id)
        group = ::Group.find_by(id: group_id)
        group ? group.users.active.to_a : []
      end

      def users_with_role(project, role_id)
        ::User.active.joins(members: :member_roles)
              .where(members: { project_id: project.id }, member_roles: { role_id: role_id }).distinct.to_a
      end

      def who_label(who = param('who'))
        case who.to_s
        when 'user' then name_of(::User, param('user_id'))
        when 'role' then l(:automation_rules_who_role_members, role: name_of(::Role, param('role_id')))
        when 'group' then l(:automation_rules_who_group_members, group: name_of(::Group, param('group_id')))
        else l("automation_rules_who_#{who}")
        end
      end

      def journal_for(issue, context)
        issue.current_journal || issue.init_journal(author(context))
      end
    end
  end
end

Dir[File.join(__dir__, 'actions', '*.rb')].each { |file| require file }
