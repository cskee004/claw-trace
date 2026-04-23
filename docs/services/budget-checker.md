# BudgetChecker

`app/lib/budget_checker.rb`

Evaluates daily LLM spend for every agent that has a budget configured and emits a console alert for any agent that has exceeded its limit.

---

## Interface

```ruby
results = BudgetChecker.check
# => [
#      #<struct BudgetChecker::Result agent_id="support-agent", spent_usd=1.42, limit_usd=5.0,  over_budget=false>,
#      #<struct BudgetChecker::Result agent_id="coding-agent",  spent_usd=8.77, limit_usd=5.0,  over_budget=true>
#    ]
```

`.check` is a class-method shorthand that creates an instance and calls `#check`.

Returns an empty array if no `AgentBudget` rows exist.

---

## Result Object

`BudgetChecker::Result` is a `Struct` with keyword initialization:

| Accessor | Type | Description |
|----------|------|-------------|
| `agent_id` | String | Agent identifier |
| `spent_usd` | Float | Total `span_cost_usd` for today (UTC, since midnight) |
| `limit_usd` | Float | Daily limit from `agent_budgets.daily_limit_usd` |
| `over_budget` | Boolean | `true` when `spent_usd > limit_usd` |
| `excess_usd` | Float (computed) | `spent_usd - limit_usd`; negative when under budget |
| `excess_pct` | Integer (computed) | Percentage over limit; 0 when under budget or limit is zero |
| `over_budget?` | Boolean | Alias for `over_budget` |

---

## How Spend Is Computed

Spend is the sum of `spans.span_cost_usd` for spans where:

- `span_model IS NOT NULL` (only model-call spans carry a cost)
- `agent_id` matches a configured budget
- `timestamp >= beginning of today (UTC)`

A single SQL `GROUP BY agent_id` + `SUM(span_cost_usd)` query covers all budgeted agents at once.

---

## Console Output

`BudgetChecker.check` prints a summary line per agent while it runs:

```
✓  support-agent — $1.42 today (limit: $5.00)
⚠️  BUDGET ALERT: coding-agent
   Spent: $8.77 today (limit: $5.00)
   Excess: $3.77 (75% over)
```

---

## Intended Usage: Cron

`BudgetChecker` is designed to run on a schedule — typically once per hour or once per day — via a system cron job:

```cron
# Check budgets every hour
0 * * * * cd /path/to/app && bin/rails runner "BudgetChecker.check" >> log/budget.log 2>&1
```

The Rails runner process starts, runs the check, prints results to stdout/log, and exits. There is no persistent daemon.

---

## Related

- `AgentBudget` model — `app/models/agent_budget.rb`
- Budget CRUD UI — Agent show page (`/agents/:id`)
- `ModelPricingService` — computes `span_cost_usd` at ingestion time
- Schema: [`agent_budgets` table](../reference/schema.md#agent_budgets)
