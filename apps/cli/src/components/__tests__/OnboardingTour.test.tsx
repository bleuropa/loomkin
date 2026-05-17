import React from "react";
import { describe, expect, test, vi } from "vitest";
import { OnboardingTour, STATIC_TOUR_PAYLOAD } from "../OnboardingTour.js";
import type { TourPayload } from "../../stores/tourStore.js";

/**
 * `useInput` from ink expects a raw-mode TTY at mount time. We mount the
 * component non-interactively (`interactive={false}`) for tests so the
 * hook is skipped, then assert by traversing the React tree directly.
 */

type ReactNode = React.ReactNode;

function elementText(node: ReactNode): string {
  if (node === null || node === undefined || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(elementText).join(" ");
  if (React.isValidElement(node)) {
    const props = (node.props as { children?: ReactNode }) ?? {};
    return elementText(props.children);
  }
  return "";
}

function render(payload: TourPayload, onClose = vi.fn()) {
  const element = OnboardingTour({ payload, onClose, interactive: false });
  return elementText(element);
}

describe("OnboardingTour", () => {
  test("renders the marquee headline and the nine canonical phases", () => {
    const text = render(STATIC_TOUR_PAYLOAD);

    expect(text).toContain("LOOMKIN ORCHESTRATION");
    for (const expected of [
      "Researcher",
      "Planner",
      "Plan Council",
      "Design Council",
      "Decomposer",
      "Executor",
      "Adversarial Reviewer",
      "PR Author",
      "Curator",
    ]) {
      expect(text).toContain(expected);
    }
  });

  test("renders the steering keys [p], [c], [r]", () => {
    const text = render(STATIC_TOUR_PAYLOAD);
    expect(text).toContain("[p]");
    expect(text).toContain("[c]");
    expect(text).toContain("[r]");
  });

  test("includes the LiveView URL for the rich version", () => {
    const text = render(STATIC_TOUR_PAYLOAD);
    expect(text).toContain("http://loom.test:4200/orchestration/tour");
  });

  test("renders empty phases array gracefully", () => {
    const text = render({ phases: [], personas: [], mark_seen_on_close: false });
    // Headline + steering keys section must still appear.
    expect(text).toContain("LOOMKIN ORCHESTRATION");
    expect(text).toContain("[p]");
  });

  test("dynamically renders persona icons from server payload", () => {
    const text = render({
      phases: [
        { phase: "research", name: "Researcher", icon: "RX", role_blurb: "gathers context" },
        { phase: "plan", name: "Planner", icon: "PX", role_blurb: "drafts the work units" },
      ],
      personas: [],
      mark_seen_on_close: true,
    });

    expect(text).toContain("Researcher");
    expect(text).toContain("Planner");
    expect(text).toContain("RX");
    expect(text).toContain("PX");
    expect(text).toContain("drafts the work units");
  });

  test("static payload contains all nine canonical phases", () => {
    expect(STATIC_TOUR_PAYLOAD.phases).toHaveLength(9);
    const names = STATIC_TOUR_PAYLOAD.phases.map((p) => p.name);
    expect(names).toContain("Researcher");
    expect(names).toContain("Curator");
  });
});
