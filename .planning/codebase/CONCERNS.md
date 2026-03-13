# Codebase Concerns

**Analysis Date:** 2026-03-07

## Tech Debt

### 1. Monolithic LiveView Component (workspace_live.ex)

**Issue:** Primary workspace UI is 4,714 lines in a single module. Contains 90+ socket assigns, complex nested state management, and multiple concerns (messaging, team management, permissions, diffs, queues, scheduling, inspection).

**Files:** `lib/loomkin_web/live/workspace_live.ex`

**Impact:**
- Extremely difficult to test individual features
- State mutations scattered throughout deeply nested handler functions
- Hard to reason about side effects and subscriptions
- Cognitive load on maintainers; change risk is high
- Performance degradation as component re-renders accumulate

**Fix approach:**
- Extract state concerns into separate LiveComponents: message panel, team roster, inspector panel, queue management, schedule popover, command palette, kin panel, file explorer
- Each LiveComponent manages its own subscriptions and state
- Workspace orchestrates higher-level coordination via send_update calls
- Reduces workspace_live.ex to ~800 lines of orchestration logic

### 2. Large Agent GenServer (agent.ex - 2,348 lines)

**Issue:** The Teams.Agent module combines GenServer lifecycle, task management, permission handling, state snapshots, and queue management in a single 2,348-line file.

**Files:** `lib/loomkin/teams/agent.ex`

**Impact:**
- Difficult to test failure scenarios and async task handling
- State reconciliation between loop_task tuple and queue management is fragile
- Adding new agent features requires modifying a massive file
- Risk of accidental task leaks if state management logic is modified

**Fix approach:**
- Extract task lifecycle management into `Agent.TaskManager` (handle task spawning, monitoring, result collection)
- Extract queue/message management into `Agent.QueueManager` (priority queue operations, reordering, deletion)
- Keep Agent as orchestrator that delegates to these modules
- Each module should be <600 lines with clear responsibilities

### 3. Architect/Session Large Modules

**Issue:** `Architect` (1,042 lines) and `Session` (777 lines) mix multiple concerns: planning, execution, persistence, context windowing, and error recovery.

**Files:** `lib/loomkin/session/architect.ex`, `lib/loomkin/session/session.ex`

**Impact:**
- Planning and execution phases are hard to test independently
- Difficult to debug which model (architect vs editor) is responsible for failures
- Adding new planning strategies requires modifying the main loop

**Fix approach:**
- Extract plan execution into `Architect.Executor` module
- Extract editor execution into `Architect.EditorPhase` module
- Create strategy pattern for different reasoning modes (ReAct, CoT, CoD, ToT)
- Keep Architect as coordinator

## Known Bugs

### 1. State Leak in ETS Token Cache During Tests

**Symptoms:** Intermittent test failures when token store tests run in sequence; tokens from one test appear in subsequent tests.

**Files:** `lib/loomkin/auth/token_store.ex`, `test/loomkin/auth/token_store_test.exs`

**Trigger:** Running multiple token store tests without clearing the `:loomkin_auth_tokens` ETS table between tests. The ETS table is created with `:named_table` and is shared across all tests, but token cleanup is not guaranteed in error paths.

**Workaround:** Add ETS table cleanup in test teardown via `on_exit` hooks. Commit `07e8176` ("fix: reset config in architect test setup to prevent ets state leak") attempted a similar fix for architect tests.

**Fix approach:**
- Add `on_exit` callback in setup_all to clear :loomkin_auth_tokens
- Ensure token revocation happens in GenServer handle_info for failed refreshes (not currently guaranteed)
- Consider using per-test token IDs to avoid collisions

### 2. Flaky Tests - Fixed But Pattern Still Present

**Symptoms:** Tests intermittently fail due to timing issues (e.g., registry polling, rate limiting, supervision trees).

**Files:** Multiple test files, recent fixes at commits `af57578`, `7fd74d4`

**Trigger:** Fixed-sleep timeouts that assume processing happens within a fixed window.

**Current status:** Fixed in latest commits (`af57578` for supervision, `7fd74d4` for rate limiter), but pattern indicates test suite is brittle to timing assumptions.

**Remaining risk areas:**
- `test/loomkin/teams/` tests that spawn multiple agents and wait for state changes
- `test/loomkin/session/` tests that poll for task completion
- Signal/PubSub tests that assume message delivery within fixed windows

**Fix approach:**
- Create shared test utilities for polling with backoff instead of fixed sleeps
- Use `ExUnit.CaptureLog` to verify events occurred rather than checking state
- Add explicit synchronization points using GenServer.call timeouts

## Security Considerations

### 1. Hardcoded Credentials in Development Config

**Risk:** Dev database credentials are committed to `config/config.exs` with default PostgreSQL values.

**Files:** `config/config.exs` (lines 5-12)

**Current mitigation:** These are dev defaults; production config comes from environment variables via `runtime.exs`.

**Recommendations:**
- Document that `config/config.exs` is for development only
- Add .env template file showing which vars must be set
- Verify runtime.exs properly overrides all sensitive config for production

### 2. In-Memory Token Decryption (Token Store ETS Cache)

**Risk:** OAuth tokens are stored decrypted in ETS memory cache. While encrypted at rest, they exist in plaintext in memory during token refresh operations and are vulnerable to process dumps.

**Files:** `lib/loomkin/auth/token_store.ex` (lines 71-82, 270)

**Current mitigation:**
- Tokens are encrypted at rest in database
- ETS table has `read_concurrency: true` but is `:protected` (not `:public`)
- Token storage limited to registered OAuth providers

**Recommendations:**
- Add documentation about memory security assumptions
- Implement token rotation policy (set reasonable expiry even if provider gives longer)
- Ensure token_store GenServer doesn't dump plaintext tokens in error logs
- Consider adding explicit token zeroization on revoke (overwrite memory before freeing)

### 3. String.to_atom Vulnerability Prevention

**Risk:** LLM-generated tool arguments could exhaust Elixir's atom table if converted naively.

**Files:** `lib/loomkin/session/architect.ex` (lines 953-955)

**Current mitigation:** Uses `Loomkin.Tools.Registry.atomize_keys/1` with known-key allowlist instead of `String.to_atom/1`.

**Status:** Properly mitigated. Document this pattern for future atom conversions.

## Performance Bottlenecks

### 1. Large Message History in WorkspaceLive Socket State

**Problem:** Socket assigns store up to 200 messages and 100 diffs in memory. As conversations grow, re-rendering and subscription processing slows.

**Files:** `lib/loomkin_web/live/workspace_live.ex` (lines 8-9, 398, 1199)

**Cause:**
- `@max_messages 200` and `@max_diffs 100` are kept in socket for real-time display
- Every new message triggers full re-render of message panel
- Diffs accumulate even when user isn't viewing them

**Improvement path:**
- Implement server-side message pagination (keep only last 50 in socket, load older on demand)
- Separate diff storage to a separate component (load on tab switch, not on every diff)
- Cache rendered HTML for messages that haven't changed
- Use `:stream` for message lists instead of full list re-render

### 2. Synchronous GenServer.call(:send_message, :infinity) Timeout

**Problem:** Agent message delivery uses `:infinity` timeout, blocking the caller until the entire agent loop completes.

**Files:** `lib/loomkin/teams/agent.ex` (line 66), `lib/loomkin/session/session.ex` (line 45)

**Cause:**
- Waiting for full agent reasoning loop response before returning
- Long model inference times (30s-2min) block caller
- If the loop times out or fails, the caller blocks indefinitely

**Improvement path:**
- Implement async result collection: GenServer.call returns immediately with task ref, caller polls for results
- Store task refs in a registry keyed by caller PID
- Alternatively, use message-based result delivery via PubSub instead of GenServer.call
- Add reasonable timeouts (15min max) for safety

### 3. Full Roster Refresh on Every Agent Event

**Problem:** Workspace debounces roster refresh to 50ms, but still recomputes cached_agents and cached_tasks on every team event.

**Files:** `lib/loomkin_web/live/workspace_live.ex` (line 10), roster refresh handlers

**Cause:** No incremental updates; always rebuild roster from scratch when any agent status changes.

**Improvement path:**
- Implement incremental roster updates (update only the agent that changed status)
- Cache roster fetch results and invalidate only on relevant events
- Batch agent status updates at 100ms intervals instead of re-querying

## Fragile Areas

### 1. Subscription Management in workspace_live.ex

**Files:** `lib/loomkin_web/live/workspace_live.ex` (lines 63-68, 175-192, 3233-3271)

**Why fragile:**
- Uses `subscribed_teams` MapSet to track subscriptions, but subscriptions can be lost if socket crashes
- `global_signals_subscribed` and `vote_signals_subscribed` flags can become out of sync with actual Signals subscriptions
- If LiveView crashes during subscription setup, PubSub topics remain subscribed but socket state is lost

**Safe modification:**
- Store subscriptions in a more explicit data structure (map of topic → subscribed_at timestamp)
- Add unsubscribe cleanup in handle_error and terminate callbacks
- Log subscription state changes for debugging
- Test coverage: unit tests for subscription state machine

**Test coverage gaps:** No tests verify that subscriptions are cleaned up on disconnect; no tests verify re-subscription after crash.

### 2. Task Lifecycle Management in agent.ex

**Files:** `lib/loomkin/teams/agent.ex` (lines 240-276, 314-350, 1700-1800)

**Why fragile:**
- `loop_task` is stored as `{%Task{}, from}` but Task monitoring can fail
- If task crashes without sending a message back, the GenServer waits indefinitely
- Task cleanup uses `Task.shutdown(task, :brutal_kill)` which may lose in-progress state
- Race condition: task completes while cancel is being handled

**Safe modification:**
- Add explicit task monitor setup with timeout
- Implement task watchdog timer that fires if no task completion seen after 2x timeout
- Use `async_nolink` but add explicit message handlers for :DOWN messages
- Store task start time and warn if loop_task duration exceeds expected bounds

**Test coverage gaps:** No tests for task timeout scenarios; no tests for task crash during pause/resume cycle.

### 3. Permission Request State in agent.ex

**Files:** `lib/loomkin/teams/agent.ex` (pending_permission, permission_mode)

**Why fragile:**
- `pending_permission` can be overwritten if new permission request arrives before user responds
- No timeout if user never responds to permission request
- Permission callbacks mix GenServer message handling with external PubSub events
- Race: user denies permission while loop is executing tool

**Safe modification:**
- Store pending permissions in a queue with timestamps and auto-timeout after 5min
- Validate permission response matches the exact pending request (use request_id)
- Add timeout handler that treats expired permissions as denied
- Block tool execution until permission response is received (not just queued)

**Test coverage gaps:** No tests for permission timeout; no tests for stale permission responses.

### 4. Context Keeper Index Injection

**Files:** `lib/loomkin/session/architect.ex` (line 1800), `lib/loomkin/teams/agent.ex` (line 1800)

**Why fragile:**
- `inject_keeper_index/2` modifies system prompt with dynamic keeper state
- If context keeper is slow or times out, system prompt becomes incomplete
- Failure is silent; malformed system prompt causes LLM errors downstream

**Safe modification:**
- Make keeper injection asynchronous: fetch keeper data before spawning loop task
- Cache keeper index for 30s to avoid repeated fetches
- If keeper fetch fails, log warning but proceed with default system prompt
- Add circuit breaker: if keeper fetch fails 3x, skip injection for next 5min

**Test coverage gaps:** No tests for keeper fetch timeout; no tests for malformed keeper index.

## Scaling Limits

### 1. PostgreSQL Connection Pool

**Current capacity:** `pool_size: 10` (from `config/config.exs` line 12)

**Limit:** Each concurrent agent session needs ~2-3 connections (task execution, context loading, decision graph updates). With 10 pool connections, maximum ~5 concurrent agent loops.

**Scaling path:**
- Monitor connection pool saturation metric
- Add backpressure: when pool utilization > 80%, queue new messages with priority
- For high-concurrency deployments, increase pool_size dynamically based on agent count
- Consider connection pooler (PgBouncer) for larger deployments

### 2. ETS Token Cache Single Provider

**Current capacity:** One ETS entry per OAuth provider (usually 1-5 providers)

**Limit:** No per-user token storage; shared provider tokens means any deployment with multiple users sharing auth tokens will have collisions.

**Scaling path:**
- Migrate token storage to include account_id in key: `{provider, account_id}`
- Add multi-tenant support to token store GenServer
- Implement token access control (user can only access own tokens)

### 3. Message Queue and Diffs in Memory

**Current capacity:** 200 messages + 100 diffs per socket

**Limit:** With 50 concurrent users, total memory ≈ 50 * (200 messages * 1KB + 100 diffs * 2KB) ≈ 10MB. At 1000 users, memory becomes a bottleneck.

**Scaling path:**
- Move message/diff storage to a distributed cache (Redis)
- Keep only recent 20 messages in socket, paginate on demand
- Archive diffs after session completes
- Implement garbage collection: delete diffs after 24 hours

## Dependencies at Risk

### 1. jido_ai on 'main' Branch

**Risk:** `jido_ai` is pinned to `main` branch instead of a release tag, making builds non-deterministic.

**Files:** `mix.exs` (line 33)

**Impact:** New jido_ai commits could break the build silently; reproducing issues across deploys is difficult.

**Migration plan:**
- Pin jido_ai to a specific commit hash with fallback to release tag when available
- Add CI check that warns if 'main' branch pins drift
- Document jido_ai release process so stable tags are created

### 2. Custom Forks of Dependencies

**Risk:** Several dependencies are forks with custom refs, increasing maintenance burden.

**Files:** `mix.exs` (lines 34, 44-45, 47)

**Affected packages:**
- `abacus` - custom ref
- `sched_ex` - custom ref
- `toml` - custom ref

**Impact:** Pulling updates from upstream becomes manual process; divergence grows over time.

**Recommendations:**
- Document why each fork is needed
- Create upstream PRs to merge changes back
- Set deadline for removing each fork (6 months)
- Use feature flags to allow gradual migration

## Test Coverage Gaps

### 1. Agent Pause/Resume Cycle

**What's not tested:** Pausing an agent mid-loop, resuming with guidance, ensuring state consistency.

**Files:** `lib/loomkin/teams/agent.ex` (pause_requested, paused_state), `test/loomkin/teams/agent_test.exs`

**Risk:** Pause/resume feature could have silent state corruption that only appears under load.

**Priority:** High - affects user-critical workflow

### 2. Permission Denial Paths

**What's not tested:** User denying tool permission while loop is executing, timeout of pending permission, stale permission responses.

**Files:** `lib/loomkin/teams/agent.ex` (permission_mode, pending_permission), `test/loomkin/permissions/`

**Risk:** Permission denial could be silently ignored or cause loop to crash.

**Priority:** High - security-relevant

### 3. Task Supervisor Failure Scenarios

**What's not tested:** TaskSupervisor crashes, child task exits with exception, brutal_kill of hung task.

**Files:** `lib/loomkin/teams/agent.ex` (Task.Supervisor calls), `test/loomkin/teams/`

**Risk:** Task cleanup failures could accumulate and cause cascading failures.

**Priority:** Medium - affects reliability

### 4. Channel Bridge Message Routing

**What's not tested:** Rate limiting edge cases, message loss under high load, callback handling with missing bridge.

**Files:** `lib/loomkin/channels/bridge.ex` (rate_limit_max, handle_inbound, handle_callback), `test/loomkin/channels/`

**Risk:** Messages lost to rate limiting without acknowledgment; callbacks routed to non-existent bridges.

**Priority:** Medium - affects external integrations

### 5. Decision Graph Concurrent Mutations

**What's not tested:** Multiple agents updating decision graph simultaneously, race conditions in node consensus.

**Files:** `lib/loomkin/decisions/graph.ex`, `lib/loomkin/teams/consensus_trail.ex`, `test/loomkin/decisions/`

**Risk:** Silent data corruption in decision graph structure; consensus algorithm could produce incorrect results under contention.

**Priority:** High - core feature

## Missing Critical Features

### 1. Graceful Shutdown of Agent Loops

**Problem:** No mechanism to shutdown all running agent loops cleanly before deploying. Tasks may be abruptly killed.

**Blocks:** Zero-downtime deployments; production reliability.

**Approach:**
- Implement agent loop checkpoint that allows graceful cancellation
- Add Supervisor that drains queued messages before shutdown
- Implement :drain signal that pauses new work but allows in-progress tasks to complete

### 2. Observability - Distributed Tracing

**Problem:** No correlation IDs or distributed trace context across agent teams and sessions.

**Blocks:** Debugging complex multi-team interactions; diagnosing latency in production.

**Approach:**
- Add trace_id to all message/event structures
- Use OpenTelemetry for span correlation
- Add `:telemetry.span` calls around long-running operations

### 3. Agent Loop Instrumentation / Metrics

**Problem:** No metrics for agent loop performance (time per iteration, tokens used, tool call count).

**Blocks:** Performance optimization; capacity planning; SLA enforcement.

**Approach:**
- Emit telemetry events at loop start, each tool call, and loop end
- Collect metrics: loop duration, tool duration, token count, success/failure rate
- Expose Prometheus metrics for Grafana dashboard

---

*Concerns audit: 2026-03-07*
