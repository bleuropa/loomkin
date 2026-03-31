import { useEffect } from "react";
import { useStore } from "zustand";
import { useSessionStore } from "../stores/sessionStore.js";
import { useAppStore } from "../stores/appStore.js";
import { useAgentStore } from "../stores/agentStore.js";
import { useConversationStore } from "../stores/conversationStore.js";
import { joinChannel } from "../lib/socket.js";

import type { ConversationInfo, Message } from "../lib/types.js";

let notifyCounter = 0;

function notify(content: string) {
  const msg: Message = {
    id: `notify-${++notifyCounter}`,
    role: "system",
    content,
    tool_calls: null,
    tool_call_id: null,
    token_count: null,
    agent_name: null,
    inserted_at: new Date().toISOString(),
  };
  useSessionStore.getState().addMessage(msg);
}

/**
 * Subscribes to agent-related events on the session channel.
 * Updates the agent store with real-time status, tool use, and task info.
 *
 * Note: Agent events are received on the same `session:<id>` channel
 * as message events — the backend forwards agent.** signals there.
 * This hook piggybacks on the existing channel connection.
 */
export function useAgentChannel() {
  const sessionId = useStore(useSessionStore, (s) => s.sessionId);
  const connectionState = useStore(useAppStore, (s) => s.connectionState);
  const isConnected = connectionState === "connected";
  const agentsMap = useStore(useAgentStore, (s) => s.agents);

  useEffect(() => {
    if (!sessionId || !isConnected) return;

    const topic = `session:${sessionId}`;
    const channel = joinChannel(topic);

    // Track subscribed event names for cleanup.
    // Phoenix channel.on() TS types don't expose the ref number,
    // so we remove all handlers per event name on cleanup.
    const subscribedEvents: string[] = [];

    function on<T>(event: string, handler: (payload: T) => void) {
      channel.on(event, handler as (payload: Record<string, unknown>) => void);
      subscribedEvents.push(event);
    }

    // --- Agent events ---

    on<{ agent_name: string; status: string }>("agent_status", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        status: payload.status,
      });
      if (payload.status === "done" || payload.status === "completed") {
        notify(`✓ ${payload.agent_name} finished`);
      }
    });

    on<{ agent_name: string; new_role: string }>("agent_role_changed", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        role: payload.new_role,
      });
    });

    on<{ agent_name: string; tool_name: string }>("agent_tool_executing", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        currentTool: payload.tool_name,
        status: "working",
      });
    });

    on<{ agent_name: string; tool_name: string }>("agent_tool_complete", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        currentTool: undefined,
      });
    });

    on<{ agent_name: string; error: string }>("agent_error", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        status: "error",
        lastError: payload.error,
      });
      notify(`⚠ ${payload.agent_name}: ${payload.error}`);
    });

    on<{ agent_name: string; tokens_used?: number; cost_usd?: number }>(
      "agent_usage",
      (payload) => {
        useAgentStore.getState().upsertAgent(payload.agent_name, {
          tokensUsed: payload.tokens_used,
          costUsd: payload.cost_usd,
        });
      },
    );

    on<{ agent_name: string; role: string; team_id: string }>("agent_spawned", (payload) => {
      useAgentStore.getState().upsertAgent(payload.agent_name, {
        role: payload.role,
        teamId: payload.team_id,
        status: "idle",
      });
      notify(`🤖 Agent ${payload.agent_name} (${payload.role}) joined the team`);
    });

    // --- Collaboration events ---

    on<{ from: string; to: string; content: string }>("peer_message", (payload) => {
      notify(`💬 ${payload.from} → ${payload.to}: ${payload.content}`);
    });

    on<{ conversation_id: string; topic: string; participants: string[]; strategy?: string; team_id: string }>(
      "conversation_started",
      (payload) => {
        useConversationStore.getState().startConversation(payload);
        const who = payload.participants.join(", ");
        notify(`🗣 Conversation started: ${payload.topic} (${who})`);
      },
    );

    on<{ conversation_id: string; speaker: string; content: string; round: number; team_id: string }>(
      "conversation_turn",
      (payload) => {
        useConversationStore.getState().addTurn({
          conversation_id: payload.conversation_id,
          speaker: payload.speaker,
          content: payload.content,
          round: payload.round,
          type: "speech",
          timestamp: new Date().toISOString(),
        });
      },
    );

    on<{ conversation_id: string; agent_name: string; reaction_type: string; brief: string; team_id: string }>(
      "conversation_reaction",
      (payload) => {
        useConversationStore.getState().addReaction(payload);
      },
    );

    on<{ conversation_id: string; agent_name: string; reason?: string; team_id: string }>(
      "conversation_yield",
      (payload) => {
        useConversationStore.getState().addYield(payload);
      },
    );

    on<{ conversation_id: string; round: number; team_id: string }>(
      "conversation_round_started",
      (payload) => {
        useConversationStore.getState().advanceRound(payload.conversation_id, payload.round);
      },
    );

    on<{ conversation_id: string; round: number; team_id: string }>(
      "conversation_round_complete",
      () => {
        // Informational — next round_started will advance
      },
    );

    on<{ conversation_id: string; team_id: string }>("conversation_summarizing", (payload) => {
      useConversationStore.getState().setSummarizing(payload.conversation_id);
      notify(`📝 Conversation summarizing...`);
    });

    on<{ conversation_id?: string; topic: string; outcome: string; summary?: unknown; team_id: string }>(
      "conversation_ended",
      (payload) => {
        if (payload.conversation_id) {
          useConversationStore.getState().endConversation({
            conversation_id: payload.conversation_id,
            outcome: payload.outcome,
            summary: payload.summary as ConversationInfo["summary"],
          });
        }
        notify(`🗣 Conversation ended: ${payload.topic} → ${payload.outcome ?? "complete"}`);
      },
    );

    on<{ conversation_id: string; tokens_used: number; max_tokens: number; team_id: string }>(
      "conversation_budget_warning",
      (payload) => {
        notify(`⚠ Conversation approaching token limit (${payload.tokens_used}/${payload.max_tokens})`);
      },
    );

    on<{ from: string; position: string; reasoning: string }>("debate_response", (payload) => {
      notify(`⚔ ${payload.from} argues: ${payload.position}`);
    });

    on<{ from: string; vote: string; reason: string }>("vote_response", (payload) => {
      notify(`🗳 ${payload.from} votes: ${payload.vote}${payload.reason ? ` — ${payload.reason}` : ""}`);
    });

    on<Record<string, never>>("team_dissolved", () => {
      useAgentStore.getState().clearAgents();
      notify("Team dissolved");
    });

    on<{ type: string; agent_name?: string; task?: string; status?: string }>(
      "team_task_update",
      (payload) => {
        if (payload.agent_name && payload.task) {
          useAgentStore.getState().upsertAgent(payload.agent_name, {
            currentTask: payload.task,
          });
        }
      },
    );

    return () => {
      // Remove all listeners to prevent ghost handlers on reconnect.
      // We remove all handlers per event since Phoenix TS types don't expose refs.
      for (const event of new Set(subscribedEvents)) {
        channel.off(event);
      }
    };
  }, [sessionId, isConnected]);

  return { agents: Array.from(agentsMap.values()) };
}
