module RedmineAutomationRules
  module Actions
    # Assigns the issue to a user, the author, the acting user, the previous
    # assignee (from the journal), nobody, or the next member of a group in
    # turn. The round-robin position is kept in the rule's state as the id of
    # the last assigned member, so members can join or leave the group.
    class SetAssignee < Base
      modes 'user', 'author', 'current_user', 'previous', 'round_robin', 'unassign'
      param 'user_id', widget: 'select', options: 'user', required: true, only_if: { mode: 'user' }
      param 'group_id', widget: 'select', options: 'group', required: true, only_if: { mode: 'round_robin' }

      def apply(issue, context)
        assignee = case mode
                   when 'unassign' then nil
                   when 'user' then find_user(param('user_id'))
                   when 'author' then issue.author
                   when 'current_user' then actor(context)
                   when 'previous' then previous_assignee(issue)
                   when 'round_robin' then next_in_rotation(issue, context)
                   end
        return if mode == 'previous' && assignee.nil?

        assign(issue, assignee)
      end

      def describe
        target = case mode
                 when 'user' then name_of(::User, param('user_id'))
                 when 'round_robin' then l(:automation_rules_round_robin_in, group: name_of(::Group, param('group_id')))
                 else mode_label
                 end
        return l(:automation_rules_action_sentence_unassign) if mode == 'unassign'

        l(:automation_rules_action_sentence_set_assignee, assignee: target)
      end

      private

      def assign(issue, assignee)
        if assignee.nil?
          fail!(l(:automation_rules_error_user_not_found)) if mode == 'user'
          issue.assigned_to = nil
          return
        end
        unless issue.assignable_users.include?(assignee)
          fail!(l(:automation_rules_error_not_assignable, user: assignee.name))
        end

        issue.assigned_to = assignee
      end

      def previous_assignee(issue)
        detail = ::JournalDetail.joins(:journal)
                                .where(journals: { journalized_type: 'Issue', journalized_id: issue.id },
                                       property: 'attr', prop_key: 'assigned_to_id')
                                .order(id: :desc)
                                .detect { |d| d.old_value.present? && d.old_value.to_s != issue.assigned_to_id.to_s }
        detail && ::Principal.find_by(id: detail.old_value)
      end

      def next_in_rotation(issue, context)
        group = ::Group.find_by(id: param('group_id'))
        fail!(l(:automation_rules_error_record_not_found, type: l(:label_group), id: param('group_id'))) unless group

        member_ids = group.user_ids
        candidates = issue.assignable_users.select { |u| u.is_a?(::User) && member_ids.include?(u.id) }.sort_by(&:id)
        fail!(l(:automation_rules_error_no_rotation_candidates, group: group.name)) if candidates.empty?

        last_id = rotation_state(context, group).to_i
        user = candidates.find { |u| u.id > last_id } || candidates.first
        remember_rotation(context, group, user)
        user
      end

      def rotation_state(context, group)
        rule(context)&.state&.dig('rotation', group.id.to_s)
      end

      def remember_rotation(context, group, user)
        current_rule = rule(context)
        return unless current_rule && !context[:dry_run]

        rotation = (current_rule.state['rotation'] || {}).merge(group.id.to_s => user.id)
        current_rule.state = current_rule.state.merge('rotation' => rotation)
      end
    end
  end
end
