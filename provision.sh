#!/bin/bash
# Prepares the local development database: core and plugin migrations, Redmine's
# default data, and a seeded project so you can start developing right away.
# Safe to run more than once: everything is find-or-create.

set -e

docker compose run --rm -e REDMINE_LANG=en redmine bin/rails db:migrate

# the dev Dockerfile overrides ENTRYPOINT, so the image's REDMINE_PLUGINS_MIGRATE
# auto-migration never runs and we have to do it explicitly here
docker compose run --rm -e REDMINE_LANG=en redmine bundle exec rake redmine:plugins:migrate NAME=automation_rules RAILS_ENV=development

# trackers, statuses, priorities, roles, workflows
docker compose run --rm -e REDMINE_LANG=en redmine rake redmine:load_default_data

# seed project1 (module enabled), members, a group, categories, a version, custom
# fields and a few issues, so pickers in the rule form have data to play with
docker compose run --rm -e REDMINE_LANG=en redmine bin/rails runner -e development "$(cat <<'RUBY'
  admin = User.find_by(login: "admin")
  admin.update_columns(must_change_passwd: false) if admin

  project = Project.find_by(identifier: "project1")
  unless project
    project = Project.new(name: "project1", identifier: "project1")
    project.trackers = Tracker.all
    project.enabled_module_names = %w[issue_tracking time_tracking automation_rules]
    project.save!
  end
  project.enabled_module_names = (project.enabled_module_names + %w[issue_tracking time_tracking automation_rules]).uniq
  project.trackers = Tracker.all if project.trackers.empty?
  project.save!

  role = Role.find_by(name: "Manager") || Role.givable.first
  developer = Role.find_by(name: "Developer") || role
  [role, developer].uniq.each do |r|
    r.add_permission!(:manage_automation_rules, :view_automation_rules)
  end

  if admin && !Member.exists?(project_id: project.id, user_id: admin.id)
    Member.create!(project: project, principal: admin, roles: [role])
  end

  users = [
    ["alice", "Alice", "Anderson", role],
    ["bob",   "Bob",   "Brown",    developer],
    ["carol", "Carol", "Clark",    developer],
    ["dave",  "Dave",  "Davis",    developer],
    ["erin",  "Erin",  "Evans",    role]
  ].map do |login, first, last, user_role|
    user = User.find_by(login: login) || User.new(login: login)
    user.firstname = first
    user.lastname = last
    user.mail = "#{login}@example.com"
    user.status = User::STATUS_ACTIVE
    user.must_change_passwd = false
    user.password = user.password_confirmation = "password123" if user.new_record?
    user.save!
    Member.create!(project: project, principal: user, roles: [user_role]) unless Member.exists?(project_id: project.id, user_id: user.id)
    user
  end

  group = Group.find_by(lastname: "Support team") || Group.create!(lastname: "Support team")
  users.first(3).each { |u| group.users << u unless group.users.include?(u) }
  Member.create!(project: project, principal: group, roles: [developer]) unless Member.exists?(project_id: project.id, user_id: group.id)

  %w[Backend Frontend].each do |name|
    IssueCategory.find_or_create_by!(project: project, name: name)
  end
  Version.find_or_create_by!(project: project, name: "1.0") { |v| v.status = "open" }

  [
    { name: "Environment", format: "string", values: nil },
    { name: "Severity",    format: "list",   values: %w[Low Medium High] },
    { name: "Stale",       format: "bool",   values: nil },
    { name: "Review date", format: "date",   values: nil }
  ].each do |attrs|
    cf = IssueCustomField.find_or_initialize_by(name: attrs[:name])
    cf.field_format = attrs[:format]
    cf.possible_values = attrs[:values] if attrs[:values]
    cf.is_for_all = true
    cf.save!
    cf.trackers = Tracker.all
    cf.save!
  end

  if project.issues.empty?
    tracker = Tracker.first
    priority = IssuePriority.default || IssuePriority.first
    [
      ["Login page throws 500 on empty password", 3],
      ["Add dark mode to the dashboard", 0],
      ["Nightly backup job silently fails", 4],
      ["Update onboarding documentation", 1],
      ["Broken link in footer", 0]
    ].each do |subject, days_ago|
      issue = Issue.new(project: project, tracker: tracker, author: admin, subject: subject, priority: priority)
      issue.description = "Sample issue created by provision.sh"
      issue.save!
      issue.update_columns(created_on: days_ago.days.ago, updated_on: days_ago.days.ago) if days_ago.positive?
    end
  end

  puts "Seeded #{project.identifier}: #{project.members.count} members, #{project.issues.count} issues"
RUBY
)"
