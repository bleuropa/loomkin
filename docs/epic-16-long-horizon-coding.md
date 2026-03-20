# Epic 16: Long-Horizon Coding

> Autonomous coding that runs for hours, days, or weeks — surviving crashes,
> accumulating intelligence, and building trust through radical transparency.

## Vision

Every AI coding tool today is a **goldfish** — brilliant in the moment, amnesiac by
design. Context resets every session. Crashes lose everything. There's no institutional
memory, no learning, no continuity.

Loomkin sits on the BEAM — the only production runtime designed for processes that
**never stop running**. Telecom switches handle millions of concurrent calls, survive
hardware failures, and upgrade code without dropping a single connection. We can build
AI coding agents with those same properties.

The goal isn't just "longer tasks." It's a qualitatively different relationship between
humans and AI: agents that remember everything, explain their reasoning, get smarter
at *your specific codebase* over time, and produce work you can trust without reviewing
every line.

---

## Current State Assessment (2026-03-19)

A codebase audit against this plan reveals **~60% of the infrastructure already exists**.
The gaps are implementation, not architectural conflicts.

### What's Shipped Since This Doc Was Written

| Epic | Impact on This Plan |
|------|-------------------|
| **Epic 13: Conversation Agents** (PR #189) | Scout/surgeon deliberation (2.3), adversarial debate (4.3) can use conversation agents directly |
| **Epic 18: Closing the Loop** (PR #198) | Keeper metadata + staleness detection + Context Library UI. Phase 1.4 is now ~85% done |
| **Epic 6.5: Speculative Execution** (in progress) | `PeerStartSpeculative`, `PeerConfirmTentative`, `PeerDiscardTentative` tools + `:speculative` task state. Ghost fleet (4.2) builds on this directly |
| **Epic 6.2: Priority Message Router** | Agent message prioritization (`:urgent`/`:high`/`:normal`/`:ignore`) — feeds scope gate urgency |
| **Cost/Budget Infrastructure** | `CostTracker` (ETS-backed per-agent/team), `RateLimiter` (token bucket + budget caps), `Learning` (velocity by task type + model) |

### Phase Readiness Summary

| Phase | Readiness | Bottleneck |
|-------|-----------|------------|
| **1: Immortal Agents** | 55% | AgentCheckpoint schema (no Postgres persistence of agent state) |
| **2: Compound Intelligence** | 15-20% | Codebase Cartography (0%) blocks predictive test failure + hypothesis scoring |
| **3: Radical Transparency** | 15-20% | Decision graph + narrative engine exist; morning briefing is ~2 weeks out |
| **4: Process Mitosis** | 80% | BEAM primitives all present. Agent state is serializable. ~50 lines of glue for forking |
| **5: Collaboration** | 10% | Multi-user LiveView is trivial; handoff/consensus need Phase 1+3 |
| **6: Self-Improving Loop** | 0% | Requires everything above |

### Critical Path

```
AgentCheckpoint schema (1.1) → Progress Journal (1.3) → Codebase Cartography (2.1)
```

Everything else is either already done, easy to add, or blocked on these three.

---

## Design Principles

1. **The BEAM is the moat.** Every major feature should exploit OTP primitives that
   competitors cannot replicate without rebuilding their runtime.
2. **Trust scales with transparency.** Developers will let AI run overnight only if
   they can audit 8 hours of work in 90 seconds.
3. **Intelligence compounds.** The 50th session on a codebase should be dramatically
   more capable than the 1st.
4. **Failures are features.** "Let it crash" means agents are designed to fail and
   recover, not to never fail.
5. **Cheap exploration, expensive execution.** Use fast models to scout, reasoning
   models to build.

---

## Core Principle: Long-Horizon is Not a Mode

Users should never need to say "start a long-horizon task" or configure anything
special. Loomkin should be naturally good at tasks of any length. Short tasks simply
don't activate the heavier machinery. The system progressively escalates its own
infrastructure as a task grows.

### How It Works: Automatic Scope Detection

> **Status: Scope detection not implemented, but budget/cost infrastructure is mature**
>
> Existing primitives that feed scope detection:
> - `CostTracker` — per-agent/team ETS-backed cost tracking (microdollar precision)
> - `RateLimiter` — token bucket per provider + per-team/agent budget caps
> - `AgentLoop` — iteration caps (default 30), budget check before each LLM call
> - `ComplexityMonitor` — per-team composite complexity score (0-100) every 60s
> - `Learning` — velocity data by task type + model (cost, tokens, duration, success rate)
> - `AgentLoop.Checkpoint` — post_llm/post_tool hooks, returns `:continue` or `{:pause, reason}`
> - Rich PubSub signals (agent, team, session) — extensible for scope/budget events
>
> Missing: scope tier classification, file-count estimation, spawn depth tracking,
> file-change tracking across task lifetime, GitHub integration for issue-based scoping.

When a user describes work, Loomkin's lead agent estimates scope before doing anything:

1. **Parse intent** — what files, modules, systems are involved?
2. **Query codebase cartography** — how interconnected are those areas? How risky?
3. **Estimate magnitude** — files likely touched, tests likely affected, dependency depth
4. **Select strategy** — one of three tiers, invisible to the user:

| Tier | Trigger (scope-based, not time-based) | What activates |
|------|---------|----------------|
| **Quick** | ~1-3 files, isolated change, low coupling | Normal agent loop, no extras |
| **Session** | ~4-15 files, moderate coupling, multiple modules | Checkpoints, progress journal, drift detection |
| **Campaign** | 15+ files, cross-module, new deps, many tests | Full task DAG, scout/surgeon, adversarial shadow, morning briefings |

The user sees the same interface regardless. The difference is what's running
underneath.

### Budget Envelopes: Don't Surprise the User

**The cardinal sin of long-horizon coding is running away with someone's time and
money.** A user who asks to fix a flaky test expects quick work, not a 3-day
refactoring crusade. Loomkin must respect the user's implied expectations.

#### The Speed Reality: AI Finishes Faster Than Anyone Thinks

Research consistently shows AI agents complete tasks much faster than human-anchored
estimates predict:

- **METR time horizons** are doubling every 4-7 months. Frontier models went from
  ~50 min (early 2025) to 8+ hour workstreams by late 2026. The key insight: "the
  time horizon is determined by the length of time a *human* would take — in most
  cases the model takes less time."
- **Anthropic's 2026 Agentic Coding Report**: Claude Code completed a complex task
  in 7 hours of autonomous work with 99.9% accuracy. Rakuten cut time-to-market
  from 24 days to 5 days (79% reduction). A Fortune 100 team cut a 9-day PR cycle
  to 2.4 days.
- **The 99.9th percentile turn duration** nearly doubled between Oct 2025 and Jan
  2026 — from under 25 minutes to over 45 minutes — showing agents are sustaining
  longer autonomous runs.
- **The trend is accelerating.** METR projects that if 2024-2025 rates continue,
  agents capable of reliable week-long autonomous work arrive in late 2026 to 2027.

**What this means for Loomkin:** Never anchor time estimates to human sprint data.
A task a human team would spend a week on might take Loomkin 2-4 hours. The budget
envelope should be based on **cost ($)** and **scope (files/tests)**, not
wall-clock time. Time is a trailing indicator — cost and scope are leading ones.

#### Envelope Design: Cost and Scope, Not Time

Every task gets an **implicit budget envelope** — a ceiling based on the *work
involved*, not how long it "should" take:

| Signal | Implied envelope |
|--------|-----------------|
| "Fix this test" / "Update the readme" | **Quick:** ~$0.50, ~3 files |
| "Add a new endpoint for X" | **Session:** ~$5, ~15 files |
| "Implement epic-12" / plan doc ref | **Campaign:** ~$20-50, scope defined by plan |
| "Refactor the notification system, take your time" | **Campaign:** explicit large scope permission |
| "I'm heading to bed, be thorough" | **Campaign:** explicit overnight permission |

The envelope is shown to the user as a brief inline estimate at the start —
not a time promise, but a scope preview: "This touches ~5 files in the auth
module. I'll check in if the scope expands beyond that."

**The rule: Loomkin can silently escalate infrastructure (checkpoints, journaling)
but must ASK before escalating scope or cost.**

Activating checkpoints or a journal costs nothing and just makes work more
resilient — that's silent. But spending 3x the estimated cost or expanding into
files the user didn't mention — that requires a check-in.

**Crucially: finishing fast is always fine.** If Loomkin estimates a session-level
task and completes it in 12 minutes, that's great — not a failure of estimation.
The envelope is a ceiling, not a target. Never pad work to fill an estimate.

#### Scope Gates

When the task's actual trajectory diverges from the estimated envelope, Loomkin
pauses and asks:

```
"I estimated this as a quick fix (~3 files), but the flaky test is caused by
shared state in test_helper.ex that affects 12 other test files. Options:

  1. Fix just this test (bandaid — may re-flake)
  2. Fix the root cause across all 12 files
  3. Fix this test now, create a follow-up task for the root cause

Which approach?"
```

The user stays in control. Loomkin shows what it learned, offers options, and waits.

#### Triggers for Scope Gates

A scope gate fires when ANY of these cross the envelope:

- **Cost:** LLM spend approaching 2x the estimated budget
- **Files:** Touching 3x more files than initially estimated
- **Failures:** 3+ consecutive test failures (the fix isn't converging)
- **Depth:** Task spawns sub-tasks that weren't in the original plan
- **Drift:** Compass agent detects work outside original intent (see 3.2)

Note: **time is not a trigger.** If Loomkin is making steady progress within scope
and budget, there's no reason to interrupt just because a clock is ticking. Speed
is a feature.

#### Velocity Learning

> **Status: ~60% — `Loomkin.Teams.Learning` already tracks velocity per task type + model**
>
> What exists: `Learning.record_task_result/1` stores success, cost_usd, tokens_used,
> duration_ms, task_type. Queries: `success_rate/2`, `avg_cost/1`, `recommend_model/1`,
> `recommend_team/1`, `top_performers/1`. Per-agent metrics in `AgentMetric` schema.
>
> What's missing: extend `AgentMetric` with `scope_tier`, `file_count`, `escalations`
> fields (~200 lines + 1 migration). Then velocity learning by scope tier is a query.

Loomkin should learn its own pace on each codebase over time:

- ~~Track actual cost and scope for completed tasks, grouped by category~~
  **PARTIAL** — cost/tokens/duration tracked via `Learning` module; scope tier + file count not yet
- After 10+ completed tasks, Loomkin has empirical data: "auth module changes on
  this codebase typically cost $1.20 and touch 4 files"
- Future estimates come from Loomkin's own history on THIS codebase, not from
  generic human sprint data
- Velocity data stored in codebase cartography (Phase 2) — improves with usage

#### Explicit Budget Override

Users can set explicit envelopes when they want:

- "Fix this, but don't spend more than $1 on it"
- "Take as long as you need, budget is $50"
- "Work on this overnight, I'll review in the morning"

These override the implicit estimate. "Take as long as you need" disables scope
gates (but drift detection still runs). "Don't spend more than $1" creates a hard
cost stop.

#### The Default Posture: Go Fast, Stay Honest

Loomkin's default should be:

- **Work as fast as possible.** Don't pad, don't sandbag, don't wait. If a task
  can be done in 8 minutes, do it in 8 minutes.
- **Stop on scope expansion, not on time.** The thing that should trigger a
  check-in is "this is bigger than we thought," not "this is taking a while."
- **Stop on uncertainty.** If overnight and unsure → hibernate and wait for morning.
  If daytime and unsure → ask the user, don't guess.
- **Stop on cost.** Approaching 2x the envelope → pause with a status update.
- **Never stop on speed.** Finishing early is always good. The user should never
  feel like Loomkin is artificially slowing down.

The user should never open Loomkin to discover it burned $40 on a task they expected
to cost $2. But they should regularly be pleasantly surprised that a "$5 task"
finished in 11 minutes for $1.80.

### Progressive Escalation (Mid-Task)

Infrastructure escalation (silent — costs nothing, adds resilience):

- Agent hits iteration 10+ on what was estimated as a quick task → enable checkpoints
- Agent touches 5+ files → start journaling
- Agent spawns a sub-team → activate conflict detection
- Session exceeds 2 hours → begin preparing a morning briefing draft
- Agent loop gets paused/resumed → clearly not a quick task, enable full campaign infra

Scope escalation (requires user check-in via scope gate):

- Task needs to touch files outside the original estimate
- LLM cost approaching 2x the estimated budget
- New sub-tasks or dependencies discovered that weren't planned
- Test suite failures suggest a deeper underlying issue

The infrastructure escalation is logged in the decision graph. The scope
escalation is a conversation with the user.

### Natural User Flows

#### Flow 1: The Chat Message (most common)

User types something in the workspace chat. Loomkin figures out the rest.

```
User: "Add OAuth login with Google and GitHub providers"

Loomkin (internally):
  → Scope estimate: auth system, routes, controllers, templates, tests, 2 external
    deps — this is a campaign
  → Creates task DAG: [research providers] → [add deps + config] → [schema changes]
    → [controller + routes] → [templates] → [tests]
  → Spawns scout agents to explore omniauth vs ueberauth approaches
  → Conversation agents deliberate on the architecture
  → Surgeon builds based on scout findings + deliberation
  → Adversarial shadow validates auth edge cases

User sees: agents working, comms feed showing deliberation, progress in task list.
User does NOT see: any configuration, mode selection, or infrastructure setup.
```

#### Flow 2: The Plan Doc Reference

User points Loomkin at an existing plan. This is the "I already know what I want" flow.

```
User: "Implement docs/epic-12-vault-primitive.md"

Loomkin:
  → Reads the plan doc, identifies 8 sub-tasks with natural ordering
  → Creates task DAG directly from the plan's structure
  → Estimates: campaign-level (8 sub-tasks, new deps, new schemas, 30+ files)
  → Activates full campaign infrastructure immediately
  → Begins with sub-task 1, respecting plan ordering
  → Morning briefings reference plan progress: "Completed sub-tasks 1-3 of 8"
```

#### Flow 3: The GitHub Issue

User links an issue. Loomkin reads it and works.

```
User: "Fix #203"

Loomkin:
  → Fetches issue from GitHub, reads description + comments
  → Scope estimate based on issue content + codebase cartography
  → If bug fix touching 1-2 files: quick tier, just fix it
  → If feature request spanning multiple systems: campaign tier
  → On completion, posts summary back to the issue as a comment
```

#### Flow 4: The Continuation ("pick up where we left off")

> **Note:** Epic 18 (PR #198) added persistent workspaces with teams and session switching.
> This flow should account for workspace-level persistence, not just session-level.

User returns after a break — hours or days later. Loomkin reconnects seamlessly.

```
User opens workspace with an existing session that has hibernated agents.

Loomkin:
  → Detects hibernated checkpoints for this session
  → Shows morning briefing of what was accomplished before hibernation
  → Shows what's remaining (from task DAG + journal)
  → User says "continue" (or just sends any message)
  → Agents resurrect from checkpoints, journal is injected as context
  → Work resumes from exact stopping point
```

The key: the user never typed "resume" or "load checkpoint." Opening the session
and sending a message is enough.

#### Flow 5: The Overnight Run

User kicks something off before bed. Trust is the product.

```
User: "Refactor the notification system to use the new signal types. I'm heading
       to bed, take your time and be thorough."

Loomkin:
  → Detects "heading to bed" as intent for autonomous overnight work
  → Campaign tier with maximum transparency settings:
    - Drift detection on tight threshold (pause and wait rather than guess)
    - Adversarial shadow enabled by default
    - Morning briefing will be generated on completion or at 7 AM, whichever first
    - Confidence tiers prepared for all changes
  → Works through the night, checkpointing every step
  → If drift detected or confidence drops below threshold: hibernates and waits
    for user rather than pushing forward into uncertain territory

User wakes up to: morning briefing, confidence-tiered PR, full decision graph.
The AI was conservative overnight — it paused on uncertainty rather than guessing.
```

#### Flow 6: The Growing Task

User starts small but the task organically expands.

```
User: "Fix the flaky test in charges_test.exs"

Loomkin starts as quick tier:
  → Reads the test, runs it 5 times, identifies the race condition
  → Fix requires changing shared state setup in test_helper.ex
  → That change affects 12 other test files
  → Progressive escalation kicks in:
    - 5+ files → journal activated
    - Test failures in other files → adversarial shadow investigates
    - Scope now 12+ files → checkpoints enabled
  → Scope gate fires: "The flaky test is caused by shared state in
    test_helper.ex that affects 12 other test files. Options:
      1. Bandaid this test only (~1 file)
      2. Fix the root cause (~12 files, ~$3)
      3. Fix this test now, follow-up task for the rest"

The user didn't plan for this. Loomkin adapted.
```

#### Flow 7: The Background Steward

No user action at all. Loomkin runs maintenance autonomously.

```
Between active sessions, low-priority steward agents:
  → Monitor dependency advisories (mix hex.audit)
  → Track test suite performance trends
  → Watch for documentation staleness (code changed, docs didn't)
  → Build/update codebase cartography from recent git history

When user opens next session:
  "Before you start — there's a moderate CVE in a dependency (1 file, ~$0.20)
   and your test suite has gotten 15% slower this week (3 new slow tests
   identified). Want me to handle either of these first?"
```

### The "How Did It Know?" Moments

The goal is that users regularly experience moments of pleasant surprise:

- "I just said 'add OAuth' and it researched two libraries, had its agents debate
  which one was better for my codebase, and then built it."
- "I came back from lunch and it had paused itself because it wasn't confident about
  a schema decision. It asked me instead of guessing."
- "I didn't ask it to fix the test — it noticed the test was flaky while working on
  something else and fixed it as a side task."
- "I linked a GitHub issue and went to bed. I woke up to a PR with a 90-second
  briefing video and a confidence-sorted review queue."
- "It remembered that last month we tried approach X and it didn't work, so this
  time it went with approach Y automatically."

---

## Phase 1: Immortal Agents (survive everything)

The foundation. Without this, nothing else works.

### 1.1 Checkpoint Hibernation

> **Status: 40% — checkpoint callbacks exist, Postgres persistence missing**
>
> What exists: `AgentLoop.Checkpoint` struct (post_llm, post_tool), `paused_state`/`frozen_state`
> tracking in Agent GenServer, pause/resume API (`request_pause/1`, `force_pause/1`, `resume/2`),
> `Workspace.Server.hibernate/1`.
>
> What's missing: `AgentCheckpoint` schema, `term_to_binary` serialization of full agent state,
> post-crash/deploy resumption flow. Agent struct has 2 non-serializable fields (`loop_task`,
> `subscription_ids`) — these are transient and should be cleared on checkpoint, rebuilt on restore.

Agents serialize their full state to Postgres and can be resurrected on-demand.

**How it works:**
- New `AgentCheckpoint` schema: messages, iteration, pending tools, task context,
  decision graph cursor, frozen_state (via `:erlang.term_to_binary/1`)
- Checkpoints written at every `post_llm` and `post_tool` checkpoint (already exist)
- On crash: supervisor restarts agent, loads latest checkpoint, injects
  "you were working on X, completed Y, continue from Z" system message
- On deploy: all running agents checkpoint → hot code reload → agents resume
- On intentional sleep: `Process.hibernate/3` for memory-efficient waiting, or full
  Postgres serialization for multi-day hibernation

**BEAM advantage:** `term_to_binary` serializes ANY Erlang term. The process mailbox
model means messages to a sleeping agent queue in Postgres and replay on resurrection.
Competitors need custom serialization for their entire agent state — BEAM gives this free.

**Schema:**
```elixir
schema "agent_checkpoints" do
  belongs_to :session, Session
  field :agent_name, :string
  field :team_id, :string
  field :iteration, :integer
  field :status, Ecto.Enum, values: [:paused, :hibernated, :crashed, :deployed]
  field :state_binary, :binary        # :erlang.term_to_binary(frozen_state)
  field :messages_snapshot, :map      # recent messages for fast resume
  field :task_context, :map           # current task + progress
  field :resume_guidance, :string     # injected on wake
  timestamps()
end
```

### 1.2 Three-Tier Memory

> **Status: 65% — all three tiers exist, no managed migration between them**
>
> What exists: GenServer state (hot), per-team ETS via `TableRegistry` with heir ownership (warm),
> Postgres `context_keepers` + `decision_nodes` + `task_journal_entries` (cold).
>
> What's missing: explicit warm→cold eviction policy, cold→warm hydration beyond keepers,
> memory pressure management, token-based state size monitoring.

A memory hierarchy that gives agents an effectively unlimited context window.

**Tiers:**
- **Tier 1 (hot):** GenServer state — immediate reasoning context, in-process
- **Tier 2 (warm):** ETS tables shared across the team — recent file contents, AST
  fragments, test results. Microsecond reads, no message passing. Uses
  `:read_concurrency` for lock-free concurrent access.
- **Tier 3 (cold):** Postgres — full project history, all prior reasoning chains,
  every decision. Queryable across sessions.

**Memory manager process:**
- Watches agent state size (token estimate)
- Auto-evicts cold data: Tier 1 → Tier 2 → Tier 3
- Pre-fetches likely-needed data up the tiers using task DAG lookahead
- Per-process GC means eviction from one agent never affects others

**BEAM advantage:** Per-process garbage collection means one agent's bloated context
doesn't cause GC pauses for other agents. ETS reads are pointer dereferences (2μs),
not Redis round-trips (2ms). The 1000x difference compounds over thousands of
coordination decisions per task.

### 1.3 Progress Journal

> **Status: 40% — task-level journal exists, per-iteration agent log missing**
>
> What exists: `Workspace.TaskJournalEntry` schema (`task_id`, `status`, `result_summary`,
> `checkpoint_json`), `checkpoint_tasks/1` in WorkspaceServer for hibernate snapshots.
>
> What's missing: `AgentJournalEntry` schema for per-iteration logging (LLM calls, tool
> executions, decisions, errors), journal replay for agent reconstruction, integration with
> morning briefing generation.

Append-only log of actions taken — what the decision graph is to reasoning, the
journal is to execution.

```elixir
schema "agent_journal_entries" do
  belongs_to :session, Session
  field :agent_name, :string
  field :team_id, :string
  field :task_id, :binary_id
  field :entry_type, Ecto.Enum,
    values: [:file_written, :file_edited, :test_run, :test_passed, :test_failed,
             :command_run, :decision_made, :hypothesis_formed, :hypothesis_resolved,
             :milestone_reached, :error_encountered, :recovered, :delegated]
  field :summary, :string            # one-line human-readable
  field :details, :map               # structured metadata
  field :confidence, :float          # 0.0-1.0
  timestamps()
end
```

**On resume:** Journal entries are injected into the system prompt as a compressed
"here's what you've already done" summary. Agent doesn't re-read files it already
processed or re-run tests it already passed.

### 1.4 Keeper Persistence & Auto-Restore

> **Status: 85% — shipped in Epic 18 (Closing the Loop, PR #198)**
>
> What exists: `ContextKeeper.rehydrate_from_db(team_id)` called during workspace init,
> DynamicSupervisor-based GenServer spawning per keeper, write-through persistence with
> debouncing, staleness detection (4-factor: time/access/relevance/confidence decay),
> auto-archive at 75+ staleness score after 7+ days.
>
> What's missing: keeper rehydration is coupled to `WorkspaceServer.get_or_create_team_id` —
> should be decoupled to Team startup for crash resilience. Keeper metadata not fully synced
> in all fields.

Context keepers already have a Postgres schema — wire up boot-time hydration.

- ~~On app start: query `context_keepers` table, spawn GenServers for each active keeper~~
  **DONE** — `rehydrate_from_db/1` queries active keepers and spawns GenServers
- ~~On keeper update: write-through to Postgres~~
  **DONE** — `store/2` with debounced persistence
- ~~Keepers now survive deploys, crashes, and restarts~~
  **DONE** — with caveat: depends on WorkspaceServer init completing
- ~~Cross-session knowledge becomes durable~~
  **DONE** — staleness scoring + auto-archive keeps knowledge sharp

---

## Phase 2: Compound Intelligence (get smarter over time)

### 2.1 Codebase Cartography

> **Status: 0% — foundational, blocks 2.2 and 2.4**
>
> `RepoIntel` exists with `RepoMap` (file relevance ranking) and `Index` (file listing
> with metadata), but these are read-only tooling — no persistent semantic map, no
> coupling tracking, no risk/churn/ownership annotations. Needs 3 new schemas
> (`CartographyNode`, `CartographyEdge`, `VelocityMetric`), a background cartographer
> agent, and a query API.

A persistent, evolving semantic map of the codebase — not just an AST, but a
**mental model**.

**What it tracks:**
- Module roles: "this is the billing engine," "this is a test helper"
- Coupling: "these 3 files always change together"
- Risk: "this function is load-bearing but poorly tested"
- Churn: "rewritten 4 times in 6 months — chronic pain point"
- Ownership: "Agent X has deep context on this module from sessions 12, 15, 23"

**How it's built:**
- Initial survey: cheap fast model reads entire codebase, builds first map
- Incremental updates: on every file change, update affected map entries
- Git archaeology: background agent reads git history, correlates changes with
  test failures, identifies hidden coupling and load-bearing fossils
- Agent contributions: as agents work, they annotate the map with discoveries

**Stored in Postgres**, queryable by any agent. New agents onboard in seconds instead
of re-reading the whole codebase. Agents develop institutional caution — avoiding
high-risk files unless necessary.

### 2.2 Hypothesis-Driven Development

Agents formulate explicit, testable hypotheses before making changes.

**Lifecycle:**
1. Agent forms hypothesis: "extracting this state machine into its own GenServer
   will reduce test suite time by 15%"
2. Hypothesis logged to decision graph with predictions
3. Change executed speculatively (existing speculative execution from Epic 6.5)
4. Tests run, metrics collected
5. Hypothesis scored: confirmed, refuted, or inconclusive
6. Failed hypotheses become **negative knowledge** — "we tried X and it didn't work
   because Y" persists for future agents

**Emergent behavior:** Over weeks, the hypothesis log becomes a corpus of "things we
tried and what happened" — empirical instincts specific to *this* codebase. Multiple
agents proposing competing hypotheses for the same problem get run in parallel.

### 2.3 Cheap Scout / Expensive Surgeon

> **Status: 30-40% — model router + conversation agents provide the foundation**
>
> What exists: `Teams.ModelRouter` with escalation chain (fast→standard→expert→architect),
> dual model system (`:model` + `:fast_model` per session), per-agent success rate tracking
> (ETS-backed). **Epic 13 conversation agents** (PR #189) can serve as the deliberation
> layer — scouts explore independently, then a conversation agent session debates findings
> before the surgeon acts.
>
> What's missing: `ScoutTeam` orchestrator, scout report aggregation, cost-benefit decision
> on whether to spawn scouts (skip for simple issues).

Multi-model ensemble for cost-effective exploration.

**Pattern:**
1. Spawn 3-5 scout agents using fast cheap models (Haiku-class)
2. Each scout explores a different approach: rough implementation, edge case
   identification, risk flagging
3. Scout reports collected (cost: ~$0.05 total)
4. Single surgeon agent (Opus-class) reviews all scout reports
5. Surgeon writes final implementation, already aware of pitfalls from all scouts

**BEAM advantage:** Spawning 5 scout processes is ~15 microseconds total. They run
concurrently with preemptive scheduling — no one scout can starve others. Process
isolation means a scout that hits an error doesn't affect siblings.

**Cost math (illustrative — adjust for current pricing):** 5 fast-model scouts +
1 reasoning-model surgeon should cost significantly less than a single reasoning-model
run exploring all paths serially, and produces better results because the surgeon sees
5 independent attempts.

### 2.4 Predictive Test Failure

Before running tests, predict which will fail and why.

- Agent analyzes the diff + codebase map
- Predicts: "changes to `billing.ex` line 45 will break `test/api/charges_test.exs`
  because the return type changed, which flows through 3 callers"
- Predictions scored after tests actually run
- Over time, builds a model of "changes to X break tests in Y" specific to THIS
  codebase — not general LLM knowledge
- Feeds back into codebase cartography (coupling data)

### 2.5 The Forgetting Agent

> **Status: ~30% — staleness scoring exists from Epic 18, needs orchestration wrapper**
>
> What exists: `ContextKeeper.compute_staleness/1` (4-factor decay model), 30-min sweep
> timer, auto-archive at threshold. `success_count`/`miss_count` tracking per keeper.
>
> What's missing: periodic entropy review of ALL stored knowledge (not just keepers),
> promotion pipeline (short-term → long-term), LLM-powered "should I forget this?"
> decisions, integration with future cartography entries.

Entropy-aware memory management — without this, every persistent system drowns in noise.

- Periodically reviews stored knowledge (codebase map, hypotheses, patterns)
- Identifies: stale entries for deleted modules, hypotheses about rewritten code,
  patterns from deprecated features
- Promotes: short-term discoveries → long-term fundamentals
- Cheap model for bulk triage, expensive model for "should I forget something
  important-looking?"
- Keeps institutional memory sharp and relevant as the codebase evolves

---

## Phase 3: Radical Transparency (build trust)

### 3.1 The Morning Briefing

> **Status: 20-30% — decision graph narrative engine exists, needs briefing generation + UI**
>
> What exists: `Decisions.Narrative` builds timelines from decision graph, `Decisions.Writeup`
> exists (untested in templates), `TaskJournalEntry` with entry_type/summary/confidence,
> sessions store `summary_message_id`.
>
> What's missing: briefing generation algorithm (aggregate journal + decisions into narrated
> walkthrough), interactive UI (expand/collapse decisions), confidence heat map, scheduling
> (detect overnight sessions, generate briefing on wake or 7 AM).

When a developer opens Loomkin after an overnight session, they see a narrated
walkthrough — not a wall of diffs.

**Generated from the decision graph + progress journal:**
- Top 3-5 decisions made, with alternatives considered
- Points where agents were uncertain and chose conservatively
- Confidence heat map over changed files
- Interactive: click any decision to expand the full deliberation transcript

**Experience:** "While you were away, we refactored the payment module. We considered
three approaches — here's why we chose option B. We flagged two areas where we'd like
your input before proceeding."

Audit 8 hours of work in 90 seconds. Drill into anything that feels off.

### 3.2 Drift Detection & Course Correction

A dedicated compass agent continuously evaluates trajectory against original intent.

- Every N commits: re-read original task description, compare against decision graph
  trajectory, compute drift score
- If drift exceeds threshold: pause and notify developer
- Notification: "Your refactoring session has expanded into the auth module. This
  wasn't in scope. Continue (here's why it makes sense) or revert and stay focused?"
- Developer can redirect, approve drift, or roll back to checkpoint

**The AI is more disciplined than you are.** It notices scope creep before you would.

### 3.3 Progressive Confidence Unveiling

Not all changes deserve equal review attention.

**Confidence tiers for every change:**
- Test coverage written by agents
- Number of deliberation rounds
- Similarity to existing codebase patterns
- Whether adversarial review found issues
- Hypothesis confirmation status

**Tiers:**
- **Auto-merge** (green): high confidence, well-tested, follows existing patterns
- **Quick review** (yellow): novel but tested, moderate confidence
- **Needs discussion** (red): creative approach, limited tests, agent wants input

**A 2,000-line PR takes 15 minutes to review** because review effort scales with
uncertainty, not diff size.

### 3.4 Temporal Bookmarks & Decision Forking

Every significant decision is a saved bookmark — not just a git commit, but the full
agent state: what they knew, what they debated, what alternatives existed.

- Developer can "rewind" to any bookmark and fork: "What if at hour 3 you had chosen
  event-sourcing instead?"
- Agents replay from that point with the alternate decision
- Loomkin diffs the two timelines — not just code, but reasoning trajectories

**BEAM advantage:** Temporal replay is natural because GenServer processes are
sequential message processors. Record the inputs, reproduce the outputs. No hidden
global state, no thread-local storage, no ambient mutation. Deterministic re-execution
from any checkpoint.

### 3.5 Session Replay Theater

Any session can be replayed as an accelerated, narrated timeline.

- Agents spawning, deliberating, coding, testing, failing, recovering
- Key moments highlighted with deliberation transcripts
- Scrubbable, searchable, filterable by agent/file/decision
- 12-hour session → 5-minute replay

**Software development becomes observable** the way manufacturing floors are.

---

## Phase 4: Process Mitosis (uniquely BEAM)

### 4.1 Agent Forking

> **Status: 85% — agent state is serializable, spawn infrastructure ready, needs fork API**
>
> What exists: `Agent.get_state/1` exports full agent state, `Manager.spawn_agent/4` creates
> agents via `Distributed.start_child` (~15μs), agent struct (27 fields) is almost entirely
> serializable — only `loop_task` (Task.t()) and `subscription_ids` are transient.
>
> What's missing: `Agent.fork/2` API (~50 lines), fork monitoring + winner promotion logic,
> child naming convention, Registry cleanup for losers.

When facing ambiguous design decisions, agents fork themselves.

**Mechanics:**
- Agent state copied to N child processes (spawn is ~3μs on BEAM)
- Each fork inherits full context: messages, decisions, task position
- Forks diverge from the decision point, exploring different approaches
- Parent monitors all forks via `Process.monitor/1`
- Winner promoted back to original agent identity in Registry
- Losers killed — instant memory reclaim, no GC pressure

**Why only BEAM:** Process spawning is microseconds, not seconds. Each fork is fully
isolated — no shared mutable state. You can fork 50 exploratory agents without
meaningful overhead. In Python/Node, this requires subprocess management, full state
serialization, and manual cleanup.

### 4.2 The Ghost Fleet

> **Status: 70% — speculative execution tools exist from Epic 6.5, needs ghost lifecycle**
>
> What exists: `PeerStartSpeculative` (start speculative task with assumed blocker output),
> `PeerConfirmTentative` / `PeerDiscardTentative` (confirm/discard speculative results),
> task schema has `:speculative` boolean and `:pending_speculative`/`:completed_tentative`
> states, `Tasks.validate_speculative_dependents/1` auto-confirms/discards on blocker completion.
>
> What's missing: task DAG lookahead (detect "B depends on A, A is 70% done"), automatic
> ghost spawning, `:erlang.process_flag(:priority, :low)` for ghost processes, ghost
> lifecycle management (auto-kill on assumption invalidation).

Speculative pre-computation with phantom agents.

- Pool of lightweight "ghost" agents running at `:low` scheduler priority
- Task DAG shows B depends on A, and A is 70% done? Ghost starts B using partial
  results from A
- Ghosts killed instantly if assumptions invalidate
- If assumptions hold, ghost work promoted to real agent state — zero wasted wall time

**Cost of wrong speculation:** ~3μs of spawn time + LLM tokens consumed. Process
overhead is literally free. You could maintain 500 ghost agents and the system
wouldn't notice.

### 4.3 Adversarial Shadow Teams

> **Status: 75% — team spawn, role system, conflict detector all ready**
>
> What exists: `Manager.create_sub_team/3` for team hierarchies, `Role` struct with
> per-role tool lists, `ConflictDetector` GenServer (file-level + approach conflict
> detection), conversation agents (Epic 13) for blue/red debate.
>
> What's missing: `:shadow` role variant (test-write-only permissions), shadow team
> registration (`{:shadow_of, blue_team_id}`), ConflictDetector exemption for shadow
> pairs (~20 lines), adversarial findings channel (struct + comms feed integration).

Red team running alongside blue team for every significant change.

- Blue team writes the code
- Red team (isolated processes, own context) tries to break it:
  edge cases, race conditions, security holes, performance cliffs
- They debate via conversation agents (Epic 13)
- Red team writes exploit tests
- Only code surviving adversarial review gets committed

**BEAM advantage:** Process isolation means red team genuinely cannot access or corrupt
blue team's state. Preemptive scheduling gives adversarial agents fair CPU time.
Decision graph records the full adversarial deliberation for audit.

**Blue/Red coordination model:**

The existing `ConflictDetector` and `claim_region` system would fire false positives
constantly since adversarial teams *need* to touch the same files. The shadow team
uses a different coordination pattern:

- **Blue owns writes, Red gets read-only + test-write.** Red team can read any file
  blue touches and write *test files only* (or to a scratch namespace). Enforced via
  role tool permissions in `role.ex` — a new `:shadow` role variant.
- **Observation mode.** Red team subscribes to blue team's `ToolComplete` signals for
  `file_write`/`file_edit`. Sees exactly what blue wrote, when, without racing.
- **Verdict channel.** Red team writes findings to a shared structure, not source files:
  `{:adversarial_finding, %{file: path, issue: description, severity: level,
  exploit_test: test_code}}`. Findings surface in the comms feed and morning briefing.
- **ConflictDetector exemption.** Shadow teams register with `{:shadow_of, blue_team_id}`.
  ConflictDetector skips file-conflict warnings for known shadow pairs.
- **Automatic test integration.** If red team writes exploit tests that pass (proving a
  bug), those tests are auto-added to the blue team's test suite. Blue team sees them
  fail and must fix them before the task can complete.

### 4.4 Hot-Swap Agent Cognition

> **Status: 95% — this is native BEAM behavior, already works**
>
> Agent GenServers are stateless in terms of module code — all logic is in `:receive`
> loop handlers. On module recompile, agents pick up new code on next message dispatch
> automatically. `update_model/2` already hot-updates model on running agents via cast.
> No code changes needed — just testing + documentation.

Upgrade agent capabilities mid-flight without losing state.

- Deploy new tool, reasoning strategy, or prompt template
- Running agents pick up new code on next `receive` iteration
- No restart, no state loss, no context reconstruction
- Works in reverse: hot-patch a buggy tool while agents are running

**The deepest moat.** Python/Node have no equivalent. Competitors must restart to
change code. For a 12-hour task, restart means losing context or paying enormous
reconstruction cost. BEAM hot code reload is a 30-year-old battle-tested VM feature.

---

## Phase 5: Collaboration at Scale

### 5.1 Session Handoff Protocol

Developers hand off sessions across timezones for 24-hour continuous development.

- Outgoing agents produce structured handoff: current state, open questions,
  decisions made/deferred, known risks, recommended next steps
- Incoming agents ingest handoff, run brief clarifying Q&A via conversation agents
- Async questions routed to outgoing developer (answers from phone)
- Morning briefing waiting when outgoing developer wakes up

**The feature never sleeps.** Each human works normal hours. AI handles context
transfer.

### 5.2 Consensus Merge Resolution

When multiple agent teams work on the same codebase, merge conflicts become
conversations.

- Conflict detected → decision graphs from both sessions pulled in
- Conversation agents from both teams' leads deliberate
- Resolution respects both intents, not just lines of code
- Developer sees: "Both sessions touched `user.ex`. Session A normalized the schema,
  Session B added preferences. Here's a merged version. Both leads agreed in a
  4-turn deliberation."

### 5.3 Multi-User Mission Control

Multiple team members observe the same agent team in real time via LiveView.

- Senior dev intervenes on architecture decisions
- Junior dev watches to learn
- PM monitors progress without interrupting
- Each viewer has independent UI state (panels, selections, filters)
- All see the same live agent events

**BEAM advantage:** Phoenix LiveView handles thousands of concurrent WebSocket
connections efficiently. Adding a viewer is just another process subscribing to
PubSub. Zero additional architecture.

### 5.4 Living Architecture Document

A persistent cartographer agent maintains documentation generated from the decision
graph — not code comments.

- Knows WHY module boundaries exist where they do
- Knows WHAT tradeoff led to the current data model
- Updates automatically as agents work
- New team member asks "why does notifications use fan-out?" → gets the actual
  deliberation transcript from session #47

**Documentation quality improves with usage** rather than decaying over time.

---

## Phase 6: The Self-Improving Loop

Everything above converges here. Loomkin coding on itself.

### 6.1 Requirements

For Loomkin to reliably improve itself:
- **Checkpoint persistence** (Phase 1) — a failing test suite doesn't lose 30 min of context
- **Progress journal** (Phase 1) — "I fixed A, B, C. Still need D, E" across sessions
- **Codebase cartography** (Phase 2) — deep semantic understanding of own architecture
- **Hypothesis-driven dev** (Phase 2) — "if I refactor X, tests should get faster"
- **Adversarial shadow** (Phase 4) — red team catches regressions before commit
- **Hot-swap cognition** (Phase 4) — improvements to agent code take effect immediately

### 6.2 The Bootstrap Cycle

1. Developer describes desired improvement (e.g., "add checkpoint persistence")
2. Scout agents explore approaches using codebase cartography
3. Conversation agents deliberate on architecture
4. Lead creates task DAG with dependencies and milestones
5. Coder agents implement, guided by hypothesis-driven development
6. Adversarial shadow team validates
7. Tests run, hypotheses scored
8. If passing: commit, hot-reload new capabilities into running agents
9. New capabilities immediately available for next task
10. Loomkin is now better at the thing it just built

**The system improves itself and immediately benefits from the improvement.**

---

## Implementation Priority

| Phase | Sub-tasks | Readiness | Impact | Dependencies |
|-------|-----------|-----------|--------|--------------|
| Phase 1: Immortal Agents | 4 (checkpoint, 3-tier mem, journal, keeper restore) | **55%** — 1.4 done, 1.2 partial | Critical | None |
| Phase 2: Compound Intelligence | 5 (cartography, hypotheses, scout/surgeon, test predict, forgetting) | **15-20%** — 2.3 partial, 2.5 partial | High | Phase 1 |
| Phase 3: Radical Transparency | 5 (briefing, drift, confidence, bookmarks, replay) | **15-20%** — narrative engine exists | High | Phase 1, partial Phase 2 |
| Phase 4: Process Mitosis | 4 (forking, ghost fleet, adversarial, hot-swap) | **80%** — BEAM primitives ready | Very High (moat) | Phase 1 |
| Phase 5: Collaboration | 4 (handoff, merge resolution, multi-user, living docs) | **10%** — PubSub/LiveView ready | Medium | Phase 1, Phase 3 |
| Phase 6: Self-Improving Loop | Integration of above | **0%** | Transformative | All above |

**Start with Phase 1.** Everything else is built on immortal agents.

### Quick Wins (No Phase 1 Dependency)

These can be built now on existing infrastructure:

| Feature | Effort | Foundation |
|---------|--------|------------|
| Scope tier detection (file count heuristics) | ~200 LOC | RepoIntel + file_search tools |
| Budget envelope enforcement via checkpoint hooks | ~150 LOC | AgentLoop checkpoints + RateLimiter |
| Scout/surgeon via conversation agents | ~1-2 weeks | Epic 13 + ModelRouter |
| Forgetting agent wrapping staleness scoring | ~1 week | Epic 18 ContextKeeper staleness |
| Morning briefing v1 from decision graph | ~1-2 weeks | Decisions.Narrative + TaskJournalEntry |
| Velocity learning with scope tiers | ~200 LOC + migration | Learning module + AgentMetric |

No time estimates are provided intentionally — Loomkin should complete each phase
as fast as its capability allows, not fill an artificial timeline. Scope and
sub-task count are the planning primitives, not calendar time.

---

## Why This is a Moat

Every idea above exploits fundamental properties of the BEAM that competitors cannot
replicate without rebuilding their runtime:

| Property | BEAM | Python/Node/Go |
|----------|------|----------------|
| Process spawn | 3μs, 2KB | Threads: ms, MB. Containers: seconds, GB |
| Process isolation | Total (no shared mutable state) | Requires OS processes |
| Crash recovery | Supervisor restarts in μs | Application-level retry |
| Hot code reload | VM-native, 30 years battle-tested | Requires restart |
| Preemptive scheduling | Fair, per-reduction | Cooperative (blocks) |
| Distribution | Transparent, built-in | HTTP/gRPC/message queues |
| Serialization | `term_to_binary` (any term) | Custom per type |
| GC | Per-process (no stop-the-world) | Global (pauses all) |

A competitor would need to either:
1. Port to the BEAM (years of Elixir/Erlang expertise)
2. Build equivalent infrastructure on their runtime (years of systems engineering)
3. Accept they cannot match these capabilities

**The combination is the moat.** Any single feature could be approximated. The emergent
behavior of all of them working together — fault-tolerant, distributed, self-healing,
hot-swappable, preemptively-scheduled AI agent teams with persistent institutional
memory — is something only the BEAM can deliver.

---

## The Tagline

> Other tools give you an AI that codes. Loomkin gives you an AI team that
> **remembers, learns, recovers, debates, and gets better at your codebase every day.**
