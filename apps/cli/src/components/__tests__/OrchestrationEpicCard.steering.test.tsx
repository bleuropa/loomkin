import React from "react";
import { describe, expect, test, beforeEach, vi } from "vitest";
import { OrchestrationEpicCard, commandForKey } from "../OrchestrationEpicCard.js";
import { epicCardStore, type EpicCard } from "../../stores/epicCardStore.js";

/**
 * Steering-key bindings + new status visual states (r14).
 *
 * We exercise the pure `commandForKey` translator directly — that's the
 * load-bearing logic. `useInput` is mounted in production but skipped in
 * test (`isFocused` defaults to false) to avoid raw-mode initialization.
 */

type ReactNode = React.ReactNode;

function elementText(node: ReactNode): string {
  if (node === null || node === undefined || typeof node === "boolean") {
    return "";
  }
  if (typeof node === "string" || typeof node === "number") {
    return String(node);
  }
  if (Array.isArray(node)) {
    return node.map(elementText).join(" ");
  }
  if (React.isValidElement(node)) {
    const props = (node.props as { children?: ReactNode }) ?? {};
    return elementText(props.children);
  }
  return "";
}

function renderText(card: EpicCard, now?: number): string {
  const element = OrchestrationEpicCard({
    card,
    now: now ?? card.started_at + 1_000,
    isFocused: false,
  });
  return elementText(element);
}

function base(): EpicCard {
  return {
    epic_id: "epic-xyz",
    current_phase: "plan",
    current_persona: { name: "Planner", icon: "📋", role_blurb: "drafts work units" },
    work_unit_count: 0,
    gate_progress: {},
    status: "monitoring",
    last_event_text: "entered plan",
    diff_summaries: [],
    started_at: 1_700_000_000_000,
  };
}

function makeCard(overrides: Partial<EpicCard> = {}): EpicCard {
  return { ...base(), ...overrides };
}

beforeEach(() => {
  epicCardStore.getState().reset();
});

describe("commandForKey", () => {
  test("p emits pause when card is monitoring", () => {
    expect(commandForKey("p", { epic_id: "e1", status: "monitoring" })).toBe(
      "/orchestration pause e1",
    );
  });

  test("p still emits pause when card is awaiting_approval", () => {
    expect(commandForKey("p", { epic_id: "e1", status: "awaiting_approval" })).toBe(
      "/orchestration pause e1",
    );
  });

  test("p is a no-op for paused / closed / failed / cancelled", () => {
    expect(commandForKey("p", { epic_id: "e1", status: "paused" })).toBeNull();
    expect(commandForKey("p", { epic_id: "e1", status: "closed" })).toBeNull();
    expect(commandForKey("p", { epic_id: "e1", status: "failed" })).toBeNull();
    expect(commandForKey("p", { epic_id: "e1", status: "cancelled" })).toBeNull();
  });

  test("c emits cancel for live cards", () => {
    expect(commandForKey("c", { epic_id: "e2", status: "monitoring" })).toBe(
      "/orchestration cancel e2",
    );
    expect(commandForKey("c", { epic_id: "e2", status: "paused" })).toBe(
      "/orchestration cancel e2",
    );
    expect(commandForKey("c", { epic_id: "e2", status: "awaiting_approval" })).toBe(
      "/orchestration cancel e2",
    );
  });

  test("c is a no-op once the card is closed / failed / cancelled", () => {
    expect(commandForKey("c", { epic_id: "e2", status: "closed" })).toBeNull();
    expect(commandForKey("c", { epic_id: "e2", status: "failed" })).toBeNull();
    expect(commandForKey("c", { epic_id: "e2", status: "cancelled" })).toBeNull();
  });

  test("r emits resume only when paused", () => {
    expect(commandForKey("r", { epic_id: "e3", status: "paused" })).toBe(
      "/orchestration resume e3",
    );
    expect(commandForKey("r", { epic_id: "e3", status: "monitoring" })).toBeNull();
    expect(commandForKey("r", { epic_id: "e3", status: "awaiting_approval" })).toBeNull();
  });

  test("a and x are only active when awaiting_approval", () => {
    expect(commandForKey("a", { epic_id: "e4", status: "awaiting_approval" })).toBe(
      "/orchestration approve e4",
    );
    expect(commandForKey("x", { epic_id: "e4", status: "awaiting_approval" })).toBe(
      "/orchestration reject e4",
    );
    expect(commandForKey("a", { epic_id: "e4", status: "monitoring" })).toBeNull();
    expect(commandForKey("x", { epic_id: "e4", status: "monitoring" })).toBeNull();
  });

  test("o is reserved for the dashboard-open future wire — null for now", () => {
    expect(commandForKey("o", { epic_id: "e5", status: "monitoring" })).toBeNull();
  });

  test("unknown keys are ignored", () => {
    expect(commandForKey("z", { epic_id: "e6", status: "monitoring" })).toBeNull();
  });
});

describe("OrchestrationEpicCard steering rendering", () => {
  test("renders the approve / reject prompt when awaiting approval", () => {
    const text = renderText(makeCard({ status: "awaiting_approval" }));
    expect(text).toContain("approve");
    expect(text).toContain("reject");
    expect(text).toContain("awaiting approval");
  });

  test("renders the resume hint when paused", () => {
    const text = renderText(makeCard({ status: "paused" }));
    expect(text).toContain("resume");
    expect(text).toContain("paused");
  });

  test("renders a cancelled banner without crashing", () => {
    const text = renderText(makeCard({ status: "cancelled" }));
    expect(text).toContain("cancelled");
  });
});

describe("epicCardStore status transitions", () => {
  const epic_id = "epic-store-state";

  test("epic 'paused' event sets card.status to paused", () => {
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "created",
      epic_id,
    });
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "paused",
      epic_id,
    });
    expect(epicCardStore.getState().cards[epic_id]?.status).toBe("paused");
  });

  test("epic 'awaiting_approval' tuple event sets card.status to awaiting_approval", () => {
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "created",
      epic_id,
    });
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: ["awaiting_approval", "approve at commit boundary"],
      epic_id,
    });
    expect(epicCardStore.getState().cards[epic_id]?.status).toBe("awaiting_approval");
  });

  test("epic 'resumed_from_pause' clears paused state back to monitoring", () => {
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "paused",
      epic_id,
    });
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "resumed_from_pause",
      epic_id,
    });
    expect(epicCardStore.getState().cards[epic_id]?.status).toBe("monitoring");
  });

  test("epic 'cancelled' event sets card.status to cancelled", () => {
    epicCardStore.getState().applyEvent({
      subtype: "epic",
      event: "cancelled",
      epic_id,
    });
    expect(epicCardStore.getState().cards[epic_id]?.status).toBe("cancelled");
  });
});

describe("commandForKey + onCommand integration", () => {
  test("OrchestrationEpicCard exposes commandForKey for the active keystroke path", () => {
    // Smoke-test that the spy receives the translated command. We invoke
    // commandForKey directly + push it through a spy because mounting Ink
    // and emulating a TTY isn't practical in vitest.
    const spy = vi.fn();
    const card = makeCard({ status: "paused" });
    const cmd = commandForKey("r", { epic_id: card.epic_id, status: card.status });
    if (cmd) spy(cmd);
    expect(spy).toHaveBeenCalledWith(`/orchestration resume ${card.epic_id}`);
  });
});
