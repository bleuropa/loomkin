# Feature Landscape

**Domain:** Multi-agent orchestration visibility and human-in-the-loop steering
**Researched:** 2026-03-07
**Confidence:** HIGH (based on direct codebase analysis + domain knowledge from platforms like LangGraph, Prefect, Temporal, and Claude's agent documentation)

---

## What's Already Built

Before categorizing new features, the codebase already has substantial foundations:

| Already Present | Evidence |
|----------------|----------|
| Inter-agent comms feed (AgentCommsComponent) | 15 event types: message, discovery, decision, task_created/assigned/complete, error, agent_spawn, question, answer, tasks_unblocked, role_changed, escalation, collab_event, channel_message |
| Agent card grid showing status + current task | AgentCardComponent — status dots, content_type, last_tool readout, pending question overlay |
| Team dashboard with agent list + task list + budget bar | TeamDashboardComponent — subscribes to agent.status, team.task.*, role.changed, escalation signals |
| Team activity feed (rich event cards) | TeamActivityComponent — tool_call, message, decision, task lifecycle, streaming, context offload |
| Pause/resume per agent | AgentCardComponent exposes pause_card_agent / resume_card_agent buttons |
| Steer on paused agent | steer_card_agent button, agent.ex `steer/2` and `inject_guidance/2` |
| Reply-to-agent from card | reply_to_card_agent button |
| Ask-user pending questions | AskUserComponent + pending_questions in WorkspaceLive state |
| Collective-decide option on questions | "Let the collective decide" button sends `__collective__` answer |
| Permission gates (approve/deny tool calls) | PermissionComponent, TrustPolicy |
| Dynamic sub-teams (parent/child hierarchy) | Teams.Manager.list_sub_teams, child_teams in WorkspaceLive |
| Agent capability bars | AgentCardComponent reads Teams.Capabilities scores |
| Cost tracking per agent and team | CostTracker, budget bar in TeamDashboardComponent |
| Queue management for agent messages | message_queue_component, agent.ex enqueue/edit_queued/reorder_queue/squash_queued/delete_queued |
| Inspector mode (auto-follow focused agent) | inspector_mode: :auto_follow, collapsed_inspector, focused_agent in WorkspaceLive |

---

## Table Stakes

Features users expect from any agent orchestration UI. Missing = product feels incomplete or broken.

| Feature | Why Expected | Complexity | Build Status | Notes |
|---------|--------------|------------|-------------|-------|
| Live agent status indicators | Can't steer what you can't see; any monitoring tool shows this | Low | Partial | Status dots exist on cards but the real-time subscription is only wired for team agents, not newly spawned dynamic sub-agents auto-joining the UI |
| Agent-to-agent message stream | The core value prop — seeing what agents say to each other | Medium | Partial | AgentCommsComponent exists but workspace_live needs to wire the bus subscription to actually pipe signals into the comms stream for dynamic sub-teams |
| Per-agent task assignment visibility | Users need to confirm agents are working on the right thing | Low | Done | TeamDashboardComponent shows task title per agent |
| Task graph status (pending/in_progress/blocked/done) | Standard in every workflow tool; users expect Kanban-style clarity | Medium | Partial | Tasks shown in dashboard list but no visual dependency graph connecting blocking relationships |
| Pause / Resume individual agents | Most basic steering control — if the agent is going wrong, stop it | Low | Done | pause_card_agent / resume_card_agent wired in AgentCardComponent |
| Human-approval gate for high-risk tool calls | File writes, shell commands, git operations — users must be able to block | Medium | Done | PermissionComponent + TrustPolicy handle per-tool approval |
| Chat injection into running sessions | Natural way to redirect: type into the team conversation | Low | Partial | Reply-to-agent exists; broadcast injection to entire team conversation not yet explicit |
| Error visibility — crashed / stuck agents | If an agent errors silently, trust collapses | Low | Partial | Error status dot and error event type exist; no escalation-to-human alert mechanism |
| Budget display with live update | Cost blowout is a real risk; users need to see it in real time | Low | Done | Budget bar in TeamDashboardComponent updates on signals |
| Agent identity colors (persistent per-agent) | Necessary for reading multi-agent feeds without confusion | Low | Done | AgentColors module assigns and caches per-agent colors |

---

## Differentiators

Features that set Loomkin apart from generic orchestration platforms.

| Feature | Value Proposition | Complexity | Build Status | Notes |
|---------|-------------------|------------|-------------|-------|
| Confidence-threshold triggered ask-user | Agent auto-pauses and asks human when uncertain — reduces hallucination drift without full stop | High | Partial | AskUserComponent and pending_questions exist; the signal pathway from agent confidence check to UI question presentation needs wiring from AgentLoop |
| Checkpoint-based approval gates | Agent pauses at critical junctures (not just errors) — human signs off before irreversible actions | High | Partial | AgentLoop checkpoint callback exists; needs a dedicated "approval gate" signal type and UI card separate from permission hooks |
| Dynamic tree spawning with UI auto-discovery | Leader spawns sub-agents that automatically appear in the UI tree — no human setup | High | Partial | Sub-team tracking in Manager and child_teams in WorkspaceLive exist; newly spawned agents need auto-subscribe + card insertion without full reload |
| Leader-directed research phase before human questions | Leader spawns research agents, synthesizes findings, then poses an informed question — avoids asking humans prematurely | High | Not built | No research sub-agent pattern exists; would require leader role config + multi-step orchestration protocol |
| Inject guidance mid-stream (non-disruptive steer) | Whisper guidance into a running agent without pausing it | Medium | Done | inject_guidance/2 in agent.ex |
| Steer on pause (redirect with context) | Pause + provide new instruction + resume — the human takes the wheel briefly | Medium | Done | steer/2 wires into resume with guidance opts |
| "Let the collective decide" fallback | When human delegates a decision back to the agent team — maintains flow without human bottleneck | Medium | Done | __collective__ answer option in AskUserComponent |
| Agent capability bars (scored by task type) | Visual signal of which agent is best suited for which task — informs task assignment | Medium | Done | Teams.Capabilities powers AgentCardComponent capability bars |
| Queue management (edit, reorder, squash before delivery) | Human curates what agents will work on before they start — prevents wasted work | High | Done | Full queue API in agent.ex, message_queue_component |
| Mission Control layout (cards grid + feeds + inspector) | "Agency cockpit" UX — everything visible at once without switching contexts | High | Partial | Layout exists in WorkspaceLive but multi-panel responsive behavior needs validation with many concurrent agents |
| OTP-native process monitoring (agent health via supervision) | BEAM advantage: agent crashes auto-restart and UI reflects this with no polling | Medium | Partial | OTP supervision exists; UI reconciliation on restart not yet wired |
| Focused-agent inspector with full thinking stream | Click an agent card to expand its full reasoning and tool output in detail | Medium | Partial | inspector_mode :auto_follow and focused_agent state exist; content_type :thinking shows thought stream |

---

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full conversation replay / audit log UI | Scope creep — decisions DAG already provides reasoning history; a full replay viewer is a separate product | Use existing DecisionGraph visualization for reasoning audit; message history already in DB |
| Multi-user collaborative steering | Concurrent human operators touching the same team creates conflict — well-defined problem for a future milestone | Single human operator per team session; explicit out-of-scope in PROJECT.md |
| Custom agent persona builder | Personality/voice customization is vanity for this milestone; focus is orchestration mechanics | Leave role configs as developer-defined presets; KinPanelComponent already has a clean preset system |
| External webhook triggers and integrations | Zapier-style automation is a different product surface entirely | Focus on web UI; Channels (Telegram/Discord) exist but are out of scope for this milestone |
| Mobile-responsive orchestration UI | The mission control density is incompatible with small screens; degraded mobile = bad first impression | Web-first; explicit out-of-scope in PROJECT.md |
| Agent "brain" configuration UI (custom system prompts) | Letting non-developers write agent system prompts in prod is risky; expertise required | Role configs remain code-level; KinPanel provides safe preset selection only |
| Real-time analytics dashboards (latency histograms, P99) | Telemetry exists but exposing performance dashboards conflates monitoring with orchestration UI | Telemetry data feeds backend metrics; cost and status are the user-visible signals |
| Per-message undo / rollback | Reversing agent actions on persisted files/git is a dangerous UI to build without careful design | Provide pause-before-irreversible via permission gates instead |

---

## Feature Dependencies

```
live agent status indicators
  → agent-to-agent message stream (need status to know who produced which message)

dynamic tree spawning with UI auto-discovery
  → live agent status indicators (new agents need status subscription on join)
  → agent-to-agent message stream (new agents must appear in comms feed)

leader-directed research phase before human questions
  → dynamic tree spawning with UI auto-discovery (research sub-agents are spawned by leader)
  → confidence-threshold triggered ask-user (research completes, then ask fires)

confidence-threshold triggered ask-user
  → checkpoint-based approval gates (both use the pause/resume/checkpoint pathway)

checkpoint-based approval gates
  → pause / resume individual agents (gates block on pause, resume releases)

steer on pause
  → pause / resume individual agents (must be paused first)

focused-agent inspector with full thinking stream
  → live agent status indicators (need status to drive focused card content_type)

OTP-native process monitoring
  → live agent status indicators (restart events must update status in UI)
```

---

## MVP Recommendation

For the milestone priority order stated in PROJECT.md (visibility first, then intervention, then dynamic trees), this translates to:

**Phase 1 — Live Visibility (table stakes foundation)**
1. Wire agent-to-agent message stream for dynamically spawned sub-teams (bus subscription gap)
2. Ensure newly spawned agents auto-insert into the comms feed and agent card grid without reload
3. Task dependency graph visual (blocked-by relationships, not just a flat list)

**Phase 2 — Human Intervention Controls (differentiators)**
4. Confidence-threshold signal pathway from AgentLoop to AskUserComponent (the agent-asks-human flow)
5. Approval gate signal type (distinct from permission hooks — a deliberate "checkpoint pause" with human release)
6. Chat injection broadcast to team conversation (not just reply-to-agent)

**Phase 3 — Dynamic Tree Spawning (differentiators)**
7. Leader research phase protocol (orienter/researcher role sequence before first human question)
8. UI auto-discovery of nested sub-teams at arbitrary depth (recursive child_team subscription)
9. OTP restart reconciliation (crashed agent reappears in UI with recovered status)

**Defer to later milestones:**
- Leader autonomously determines tree depth without human config (needs cost-bounded complexity heuristic)
- Multi-user collaborative steering
- Full conversation replay UI

---

## Sources

- Direct codebase analysis: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/` (agent_comms_component.ex, agent_card_component.ex, team_dashboard_component.ex, team_activity_component.ex, ask_user_component.ex, workspace_live.ex)
- Direct codebase analysis: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/agent.ex` (pause/resume/steer/queue API)
- Direct codebase analysis: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/manager.ex` (sub-team tracking)
- Project requirements: `/Users/vinnymac/Sites/vinnymac/loomkin/.planning/PROJECT.md`
- Domain knowledge: LangGraph human-in-the-loop patterns (interrupt/approve/resume), Anthropic agent best practices (checkpoint-based control, confidence escalation), Temporal/Prefect approval gate patterns — MEDIUM confidence (training data, not verified against current docs due to web access restrictions)
