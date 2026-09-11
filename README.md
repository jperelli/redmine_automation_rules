<p align="center"><img src="doc/logo.png" alt="Redmine Automation Rules logo" width="160"></p>

# Redmine Automation Rules [![Test](https://github.com/jperelli/redmine_automation_rules/actions/workflows/test.yml/badge.svg)](https://github.com/jperelli/redmine_automation_rules/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**No-code automation rules for Redmine.** *When* an issue is created, updated, closed, reopened, gets time logged, or on a schedule; *if* it matches some conditions (tracker, status, priority, assignee, dates, custom fields, ...); *then* do something (set fields, add a note, add watchers, close it, create a subtask, send an email, call a webhook, update the parent). A project manager builds the rules in a form, without writing Ruby.

- Event triggers (issue created / updated / closed / reopened, time entry logged) and scheduled triggers (every N minutes, hours, days or weeks at a time of day).
- Conditions on every core issue field and on custom fields of every format. Actions for every core field, notes with `{{issue.subject}}` variables, watchers, subtasks, emails and webhooks.
- Built-in recipes: auto-close resolved issues, reopen on feedback, close parent when subtasks are done, round-robin assignment, escalation, due-date reminders, stale issues and more.
- Scheduled rules run from cron, **without cron** (checked on web requests) or from any external scheduler through a check URL, exactly like [Redmine Periodic Task](https://github.com/jperelli/Redmine-Periodic-Task).
- Per-rule execution log, global scheduler log, dry run ("Test on issue"), REST API.
- Redmine 5.1 to 7.0 tested in CI, MIT license.

> Work in progress: this is the initial scaffold. The rule engine, UI and API land in the following pull requests.

## Installation

Run these from your Redmine root. The paths below assume `/opt/redmine`, adjust them to yours:

    cd /opt/redmine
    git clone https://github.com/jperelli/redmine_automation_rules.git plugins/automation_rules
    bundle install
    bundle exec rake redmine:plugins:migrate NAME=automation_rules RAILS_ENV=production

Then restart Redmine so it loads the plugin. Enable the *Automation rules* module on a project: the project gets an *Automation* tab.

## Development

Run `docker compose build`, then `./provision.sh` (it creates the database, loads Redmine's default data and seeds a project with sample users and custom fields) and `docker compose up -d redmine`.

Then go to http://127.0.0.1:3000/ and log in with

    user: admin
    pass: admin

You should see a project named *project1* with the *Automation rules* module enabled.

Tests run in docker too, against the Redmine version of your choice:

    docker build -f Dockerfile.test --build-arg REDMINE_TAG=7.0-bookworm -t automation-rules-test .
    docker run --rm automation-rules-test

## Authors

  - [Julian Perelli](https://jperelli.com.ar/)

## License

MIT
