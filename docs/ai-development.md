# AI Development

ClawTrace was built almost entirely with [Claude Code](https://claude.ai/code) across 145+ tasks. This documents the workflow that kept it coherent across sessions — specifically the part that usually breaks: context drift.

## The problem

AI-assisted development has a known failure mode. The model invents methods that don't exist, forgets decisions made two sessions ago, and gradually diverges from the actual codebase. By task 50, you're spending more time correcting the AI than writing code.

The fix is simple: a small set of files the AI reads at the start of every session.

## The three files

**`CLAUDE.md`** — Instructions to the AI. Commands to run, conventions, gotchas discovered the hard way, what's off-limits, and task management rules. This is the file the AI checks before doing anything. The Gotchas section alone saves hours — each entry represents a real mistake that happened and was documented so it wouldn't happen again.

**`.claude/resources/AI_ARCHITECTURE.md`** — Architecture reference. Defines the data model, ingestion path, service layer responsibilities, and what must never happen. The AI checks this before proposing changes. It prevents hallucinated patterns: "why not add a service here?" stops when the AI knows exactly why each layer exists and what it's not responsible for.

**`.claude/resources/AI_TASKS.md`** — Numbered task log. Every task gets a number when work begins. That number appears in every commit. Completed tasks stay in the file permanently — the history is the point.

## The workflow

```
Pick backlog item → assign next task number → move to In Progress
→ work task → commit with (Task N) → run tests (0 failures) → move to Completed
```

The rule that matters most: backlog items have no numbers. A task gets a number only when work begins, using the next available integer. Numbers are permanent — they appear in git history and never change.

Every commit message follows the same format:

```
type: short description (Task N)
```

## Documentation discipline

When code changes, documentation changes. Not eventually — in the same task.

- New OTLP attributes → update `docs/api/otlp.md`
- New features → update README features section
- New service classes → update `AI_ARCHITECTURE.md`
- Discovered gotchas → add to `CLAUDE.md` Gotchas section

The architecture file is a cross-check mechanism. If you add a new span type to the code, verify the constant name matches what `AI_ARCHITECTURE.md` says. Drift between the reference file and the actual codebase is how the model goes wrong in the next session.

## Adapting for your project

If you want to run this pattern on a new project:

- **CLAUDE.md**: Start with commands (setup, test, lint), then conventions (where does business logic live?), then gotchas (what burned you?), then off-limits (what should the AI never touch without asking?). Keep it honest — the file is most useful when it reflects actual mistakes, not aspirational rules.

- **AI_ARCHITECTURE.md**: One section per system layer. Describe what each component is responsible for, and what it is not. "Do not bypass X for Y" is often the most load-bearing sentence in the file.

- **AI_TASKS.md**: Keep the full history. A file with 50 completed tasks tells the AI exactly which patterns are established and which edge cases have been handled. A clean file tells it nothing.

- **Off Limits section**: Be specific. Not "don't change the database" — "do not run `db:drop` or `db:schema:load`, use migrations only." The boundary between "suggest freely" and "ask first" is where most AI drift originates.

- **Task numbers in commits**: They look like overhead until you're debugging a regression six weeks later and `git log` shows you exactly which task introduced it.

The system is three files and one rule. The rule: don't start work without a task number and don't close a task with failing tests. Everything else follows from that.

## Task-specific prompt sequences

The anti-drift system handles ongoing development. For complex one-time operations, the same checkpoint discipline applies but takes a different form: a staged prompt sequence where each step audits before it acts and stages changes for review before committing.

[`.claude/docs/AI_MIGRATION.md`](.claude/docs/AI_MIGRATION.md) shows a real example — how ClawTrace was extracted from a combined Rails codebase (`log-analyzer`) into a standalone repo using six prompts. Prompt 1 categorizes every file. Prompt 2 verifies the categorization against actual imports and routes. Prompt 3 runs `git filter-repo` on a fresh clone. Prompts 4 and 5 clean each side independently. Prompt 6 runs the test suite on both before anything is pushed.

The structure is reusable for any repo split. The key is the gate between each step: the AI doesn't cut until the audit is confirmed, doesn't push until both test suites pass.
