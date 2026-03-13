# Loomkin: Agent Orchestration Visibility & Control

## What This Is

Loomkin is a multi-agent AI workspace built on the BEAM that lets humans orchestrate autonomous agent teams with real-time visibility and elegant steering. This milestone enhances the existing Teams layer to provide live agent-to-agent communication visibility, dynamic tree-structured agent hierarchies, and multiple human intervention patterns — all through a LiveView-powered web UI.

## Core Value

Humans can see exactly what agents are doing and saying to each other in real-time, and intervene naturally at any moment — without breaking the autonomous flow.

## Requirements

### Validated

- ✓ Multi-agent team orchestration with lead/specialist/observer roles — existing
- ✓ Jido Signal Bus for typed inter-agent communication — existing
- ✓ Peer tools (PeerAskQuestion, PeerReview, CollectiveDecision) — existing
- ✓ AgentLoop ReAct pattern with tool execution — existing
- ✓ Team supervisor with OTP fault tolerance — existing
- ✓ Task graph with dependencies (TeamTask, TeamTaskDep) — existing
- ✓ Context Keeper for overflow management — existing
- ✓ Decision graph for persistent reasoning memory — existing
- ✓ LiveView workspace with chat UI — existing
- ✓ Cost tracking per agent — existing

### Active

- [ ] Live agent-to-agent message stream visible in the web UI
- [ ] Real-time team activity dashboard showing agent status, tasks, and progress
- [ ] Human can inject messages into team conversations (chat injection)
- [ ] Human can issue direct commands to agents (pause, reassign, redirect)
- [ ] Approval gates where agents pause and await human sign-off at critical junctures
- [ ] Agents auto-ask humans when uncertain (confidence threshold triggers)
- [ ] Dynamic tree spawning — leader recursively creates child agents based on complexity
- [ ] Leader agent performs initial analysis with research sub-agents before posing questions to humans
- [ ] Agent tree depth determined autonomously by leader based on task complexity

### Out of Scope

- Discord/Telegram orchestration UI — web UI only for this milestone
- Shared/collaborative sessions with multiple humans — future milestone
- Mobile interface — web-first
- Custom agent personality/persona system — not needed for orchestration
- External workflow integrations (Zapier, webhooks) — not this milestone

## Context

Loomkin already has a working Teams layer with GenServer-based agents, Jido Signal Bus for communication, and peer tools for collaboration. The core infrastructure is solid. What's missing is the human-facing layer: the ability to watch agents work together in real-time and intervene naturally.

The BEAM gives us unique advantages here — each agent is a supervised process, message passing is native, and we can leverage OTP patterns (supervision trees, monitors, process links) to build agent hierarchies that no other platform can match.

The existing web UI (`LoomkinWeb.WorkspaceLive`) handles solo sessions well. This work extends it to show team dynamics — agent-to-agent messages, task progress, decision points, and human intervention controls.

Priority order: live visibility first, then human intervention controls, then dynamic tree spawning.

## Constraints

- **Tech stack**: Elixir/Phoenix LiveView — build on existing architecture, no new frameworks
- **Build on existing**: Enhance the working Teams layer, don't rewrite it
- **BEAM-native**: Leverage OTP supervision, process monitoring, and message passing — don't fight the platform
- **Performance**: Real-time updates must not degrade UI responsiveness with many concurrent agents
- **Branch**: Work is on `vt/visibility` branch

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Web UI only for orchestration | Focus power-user experience in one place; chat platforms later | — Pending |
| Build on existing Teams layer | Core GenServers work; enhance rather than rewrite | — Pending |
| Leader autonomously decides tree depth | Reduces human cognitive load; bounded by cost tracking | — Pending |
| Live visibility is top priority | Must see what agents do before you can steer them | — Pending |
| Both confidence-based and checkpoint-based human triggers | Different situations need different intervention patterns | — Pending |

---
*Last updated: 2026-03-07 after initialization*
