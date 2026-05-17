import { expect, test, beforeEach } from "vitest";
import { useTourStore, type TourPayload } from "../tourStore.js";

function samplePayload(): TourPayload {
  return {
    phases: [
      { phase: "research", name: "Researcher", icon: "🔬", role_blurb: "gathers context" },
      { phase: "plan", name: "Planner", icon: "📋", role_blurb: "drafts the work units" },
    ],
    personas: [],
    mark_seen_on_close: true,
  };
}

beforeEach(() => {
  useTourStore.getState().reset();
});

test("starts closed with no payload", () => {
  const state = useTourStore.getState();
  expect(state.open).toBe(false);
  expect(state.payload).toBeNull();
});

test("openTour sets open=true and stores the payload", () => {
  const payload = samplePayload();
  useTourStore.getState().openTour(payload);

  const state = useTourStore.getState();
  expect(state.open).toBe(true);
  expect(state.payload).toEqual(payload);
});

test("close flips open back to false but does not wipe the payload", () => {
  const payload = samplePayload();
  useTourStore.getState().openTour(payload);
  useTourStore.getState().close();

  const state = useTourStore.getState();
  expect(state.open).toBe(false);
  // payload kept around so closing the overlay doesn't lose user context if
  // we re-open in the same session.
  expect(state.payload).toEqual(payload);
});

test("reset wipes both open and payload", () => {
  useTourStore.getState().openTour(samplePayload());
  useTourStore.getState().reset();

  const state = useTourStore.getState();
  expect(state.open).toBe(false);
  expect(state.payload).toBeNull();
});

test("openTour replaces an existing payload", () => {
  const first = samplePayload();
  const second: TourPayload = {
    ...first,
    phases: [{ phase: "execute", name: "Executor", icon: "🛠", role_blurb: "runs work units" }],
    mark_seen_on_close: false,
  };

  useTourStore.getState().openTour(first);
  useTourStore.getState().openTour(second);

  const state = useTourStore.getState();
  expect(state.open).toBe(true);
  expect(state.payload).toEqual(second);
  expect(state.payload?.mark_seen_on_close).toBe(false);
});
