import React from "react";
import { Box, Text, useInput } from "ink";
import { useTourStore, type TourPayload } from "../stores/tourStore.js";

interface Props {
  payload: TourPayload;
  /** Invoked when the user dismisses with Enter or `q`. */
  onClose: () => void;
  /** Optional override; set in tests so `useInput` isn't mounted. */
  interactive?: boolean;
}

/**
 * Rich walkthrough card rendered inside the CLI feed when a user triggers
 * their first `:complex_task` (or runs `loomkin orchestration tour`).
 *
 * Mirrors the Tour content lives in `OrchestrationTourLive` on the server —
 * keep the two in sync.
 */
export function OnboardingTour({ payload, onClose, interactive = true }: Props) {
  // Render-only mode used by tests: avoid useInput entirely so we don't
  // require an Ink stdin context. In production we always pass
  // `interactive=true` (the default), so the interactive wrapper is what
  // actually mounts. Tests render the body directly via
  // `renderOnboardingTourBody` to skip the hook.
  if (interactive) {
    return (
      <OnboardingTourInteractive payload={payload} onClose={onClose}>
        {renderOnboardingTourBody(payload)}
      </OnboardingTourInteractive>
    );
  }

  return renderOnboardingTourBody(payload);
}

function OnboardingTourInteractive({
  payload: _payload,
  onClose,
  children,
}: {
  payload: TourPayload;
  onClose: () => void;
  children: React.ReactElement;
}) {
  useInput((input, key) => {
    if (key.return || input === "q" || input === "Q" || key.escape) {
      onClose();
    }
  });

  return children;
}

/**
 * Pure render helper. Exported for unit tests so they can drive the body
 * directly without mounting `useInput` (which requires an Ink stdin
 * context).
 */
export function renderOnboardingTourBody(payload: TourPayload): React.ReactElement {
  const phases = payload.phases ?? [];

  return (
    <Box
      flexDirection="column"
      borderStyle="round"
      borderColor="magenta"
      paddingX={2}
      paddingY={1}
      marginBottom={1}
    >
      <Box>
        <Text bold color="magenta">
          LOOMKIN ORCHESTRATION
        </Text>
      </Box>

      <Box marginTop={1}>
        <Text>
          When you ask Loomkin to do something substantial — implement a feature, fix a bug,
          refactor a module — your request runs through a 9-phase pipeline. Each phase is run by a
          named "persona" with one job:
        </Text>
      </Box>

      <Box flexDirection="column" marginTop={1}>
        {phases.map((p) => (
          <Box key={p.phase}>
            <Box width={4}>
              <Text>{p.icon}</Text>
            </Box>
            <Box width={20}>
              <Text bold>{p.name}</Text>
            </Box>
            <Text dimColor>{p.role_blurb ?? ""}</Text>
          </Box>
        ))}
      </Box>

      <Box marginTop={1}>
        <Text>
          Each work unit runs implement → validate → review → commit. Validation runs INSIDE the
          orchestrator (never inside the worker that produced the code). Reviewers cite file:line
          evidence. The system retries up to 5 times with different settings before asking you for
          help.
        </Text>
      </Box>

      <Box flexDirection="column" marginTop={1}>
        <Text bold>You stay in control:</Text>
        <Text>
          {"  • "}
          <Text color="cyan">[p]</Text> pause an in-flight epic anytime
        </Text>
        <Text>
          {"  • "}
          <Text color="cyan">[c]</Text> cancel and clean up the worktree
        </Text>
        <Text>
          {"  • "}
          <Text color="cyan">[r]</Text> resume from pause
        </Text>
        <Text>{'  • Set Settings → "Approve at commit" if you want to gate every merge'}</Text>
      </Box>

      <Box marginTop={1} flexDirection="column">
        <Text dimColor>Press [Enter] or [q] to dismiss this tour, or visit</Text>
        <Text dimColor>{"  http://loom.test:4200/orchestration/tour"}</Text>
        <Text dimColor>to see it again.</Text>
      </Box>
    </Box>
  );
}

/**
 * Static mirror of the server-side `Loomkin.Orchestration.Personas` +
 * `Loomkin.Orchestration.phases/0`. Used by the `loomkin orchestration
 * tour` CLI subcommand so we don't need a network round-trip just to
 * render the walkthrough.
 *
 * Keep in sync with `loomkin-server/lib/loomkin/orchestration/personas.ex`.
 */
export const STATIC_TOUR_PAYLOAD: TourPayload = {
  phases: [
    {
      phase: "research",
      name: "Researcher",
      icon: "🔬",
      role_blurb: "gathers context from your project",
    },
    { phase: "plan", name: "Planner", icon: "📋", role_blurb: "drafts the work units" },
    {
      phase: "plan_review",
      name: "Plan Council",
      icon: "⚖️",
      role_blurb: "feasibility · completeness · scope",
    },
    {
      phase: "design_review",
      name: "Design Council",
      icon: "🏛",
      role_blurb: "PM · architect · designer · security · CTO",
    },
    {
      phase: "decompose",
      name: "Decomposer",
      icon: "🧩",
      role_blurb: "splits the plan into work units",
    },
    {
      phase: "execute",
      name: "Executor",
      icon: "🛠",
      role_blurb: "runs each work unit through the pipeline",
    },
    {
      phase: "final_review",
      name: "Adversarial Reviewer",
      icon: "🔬",
      role_blurb: "DoD verification with file:line evidence",
    },
    { phase: "pr", name: "PR Author", icon: "📤", role_blurb: "opens the pull request" },
    { phase: "closure", name: "Curator", icon: "📚", role_blurb: "extracts learnings" },
  ],
  personas: [],
  mark_seen_on_close: false,
};

/**
 * Mounts the overlay reading the global tour store. Returns `null` when
 * the store is closed.
 */
export function OnboardingTourOverlay({ onMarkSeen }: { onMarkSeen: () => void }) {
  const open = useTourStore((s) => s.open);
  const payload = useTourStore((s) => s.payload);
  const close = useTourStore((s) => s.close);

  if (!open || !payload) return null;

  const handleClose = () => {
    if (payload.mark_seen_on_close) {
      onMarkSeen();
    }
    close();
  };

  return <OnboardingTour payload={payload} onClose={handleClose} />;
}
