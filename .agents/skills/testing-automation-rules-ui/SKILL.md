---
name: testing-automation-rules-ui
description: How to run and UI-test the Redmine Automation Rules plugin locally (docker compose), including the scheduler entry points, the REST API and locale checks.
---

# Testing the Automation Rules plugin UI

## Start Redmine with the plugin
Ruby is usually not on the host; everything runs in docker.
```
docker compose build
./provision.sh                 # migrations, default data, seed project1/users/group/custom fields/sample issues and rules
docker compose up -d redmine
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/   # wait for 200
```
Login: admin / admin at http://localhost:3000/login (Redmine may force a password change on first login).

### Schema changes in disposable local databases
- Compose bind-mounts `.volumes/sqlite`; `docker compose down -v` does not remove that host database.
- If a development migration is rewritten under an already-used version, inspect the actual schema before testing.
  For a disposable fixture database only, stop compose, preserve a backup of `.volumes/sqlite/redmine.db`,
  then move it aside and rerun provisioning/startup. Do not reset a database containing user data.
- The database file can be container-owned; use a temporary container with the same bind mount if host
  permissions prevent making the backup.

### Where things are
- Project tab: *Automation* → `/projects/project1/automation_rules`. New rule: `.../automation_rules/new`,
  recipes: the *New rule from recipe* dropdown on the list. Detail with execution log: `.../automation_rules/<id>`.
- Admin list (global rules + every project's rules): Administration > Automation rules (`/admin/automation_rules`).
  Global rules (admin only, `project_id NULL`) live under `/automation_rules/...`.
- Plugin settings, scheduler mode, check URL, *Run checker now* and the scheduler log:
  Administration > Plugins > Automation Rules > Configure (`/settings/plugin/automation_rules`).
- Issue page sidebar: an *Automation* block lists the rules that fired on the issue (needs the
  `view_automation_rules` or `manage_automation_rules` permission and the module enabled).

### Scheduler and REST entry points
- Event rules (issue created/updated/closed/reopened, time entry logged) fire inline when the issue is saved;
  they do not depend on the scheduler. Scheduled rules do.
- CLI checker: `docker compose exec redmine bundle exec rake redmine:check_automation_rules RAILS_ENV=development`.
- Web scheduler: set *Scheduler* to *Automatic on web requests* on the settings page, lower the interval to 1
  minute, wait a minute and load any page; the scheduler log gets a *Web request* row.
- Check URL: enable *Enable WS for repository management* (`/settings?tab=repositories`, or the Integrations
  tab on Redmine 6.1+) and call `GET|POST /automation_rules/check?key=<sys API key>`.
- REST: `/projects/project1/automation_rules.json`, `.../automation_rules/<id>.json`,
  `POST .../automation_rules/<id>/run_now.json`, `POST .../automation_rules/<id>/test.json?issue_id=N`.
  Enable the REST API at `/settings?tab=api` (Integrations tab on 6.1+) and authenticate with an API key.

### Browser evidence and Redmine conventions
- `init.rb`, `config/locales/*.yml`, `lib/`, helpers and controllers are loaded at boot only. After editing
  them run `docker compose restart redmine` (then wait for HTTP 200). Views and assets reload on the fly.
- The rule form builds condition/action rows with plain JS from a JSON schema embedded in the page; the
  value widget changes with the selected field and operator. Rows with a blank type are dropped on save.
- *Run now*, *Toggle* and *Delete* links use native `confirm()` dialogs.
- Tracker/status/priority names (Bug, New, Normal…) are DB data, not i18n — they stay English regardless of locale.

## Locale testing tips
- Switch language via My account > Language (http://localhost:3000/my/account). The change is immediate.
- The project tab uses `label_automation_rules_menu`; the module checkbox and permissions use
  `project_module_automation_rules` / `permission_manage_automation_rules` / `permission_view_automation_rules`.
- Module/permission names are checked at Project > Settings (Modules fieldset) and at the permissions report
  http://localhost:3000/roles/permissions.

## Devin Secrets Needed
None (local docker, default admin/admin).
