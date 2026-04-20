# AI Migration Prompt Sequence

ClawTrace started life as a feature inside a combined Rails app called `log-analyzer`. When it became clear ClawTrace was its own product, it needed to be extracted into a standalone repo — cleanly, without breaking either codebase.

This is the prompt sequence used to do that with Claude Code. Each prompt is a discrete checkpoint: the AI audits before it acts, verifies before it cuts, and stages every change for review before committing. If anything goes wrong at step 3, the original repo is untouched.

The pattern applies to any repo split, not just this one. Substitute your own app names and file categories.

---

**Prompt 1: Categorize**

List all files in this repo using `git ls-files`. For each file, categorize it as:
- CLAWTRACE: belongs exclusively to the ClawTrace app
- LOG-ANALYZER: belongs exclusively to the log-analyzer
- SHARED: used by both

Pay special attention to Rails conventions:
- app/models, app/controllers, app/views, app/jobs, app/mailers
- lib/ and lib/tasks/
- config/initializers/, config/routes.rb
- db/migrate/
- spec/ or test/ directories

Output the result as three clearly labeled lists. Do not move or modify any files yet.

---

**Prompt 2: Verify**

Review the file categorization from the previous step. Verify by checking:
- require/require_relative statements in lib/ files
- Rails autoloading — check app/ namespaces for cross-references
- config/routes.rb for routes belonging to each app
- config/initializers/ for initializers that configure one or both apps
- Gemfile — flag any gems that are only needed by one side

Show any corrections and produce a final confirmed list before proceeding.

---

**Prompt 3: Filter**

Using `git filter-repo`, create a filtered clone of this repo that contains only
the CLAWTRACE and SHARED files identified in the audit. Run this on a fresh clone
in a temp directory — do not modify the current repo. Show the exact commands
being run and confirm the resulting file list matches expectations.

---

**Prompt 4: Prepare the new repo**

In the filtered clone, prepare it to become the standalone ClawTrace Rails app:
1. Update Gemfile: set name, description, homepage, and remove any log-analyzer-specific gems
2. Ensure the Rails structure is correct — check config/application.rb, config/routes.rb
3. Add a comment header to each SHARED utility file noting it was duplicated from the original repo and changes are now independent
4. Check config/routes.rb and config/initializers/ — remove anything that belongs to log-analyzer
5. Check lib/tasks/ — remove any Rake tasks that belong to log-analyzer
6. Do not push anything yet — show a summary of all changes made

---

**Prompt 5: Clean the original**

In the original log-analyzer repo:
1. Remove all files categorized as CLAWTRACE-only in the audit
2. Remove any CLAWTRACE-only routes from config/routes.rb
3. Remove any CLAWTRACE-only initializers from config/initializers/
4. Remove any CLAWTRACE-only migrations — do not roll them back, just remove the migration files if they haven't been run in production
5. Remove CLAWTRACE-only gems from the Gemfile and run `bundle install`
6. Leave SHARED files in place
7. Update README.md to add a note pointing to the new ClawTrace repo
8. Stage all changes and show the full diff — do not commit yet

---

**Prompt 6: Sanity check before push**

Before any pushes, do a final sanity check on both repos:

New ClawTrace repo:
- Run `bundle install`
- Run `rails db:schema:load RAILS_ENV=test`
- Run `rspec` or `rails test`
- Run `bundle exec rake` for any custom Rake tasks

Original log-analyzer repo:
- Run `bundle install`
- Run `rails db:schema:load RAILS_ENV=test`
- Run `rspec` or `rails test`
- Check for any remaining references to ClawTrace constants, classes, or routes using `grep -r "ClawTrace" .`

Report all failures and any cross-references found. Only confirm ready-to-push if both repos pass cleanly.
