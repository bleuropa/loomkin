import { create } from "zustand";

/**
 * Onboarding tour overlay state.
 *
 * Driven by two sources:
 *
 *   1. The first `:complex_task` a user dispatches — the server emits
 *      `session.orchestration.tour_needed` which the SessionChannel
 *      forwards as the `orchestration_tour` push. The handler in
 *      `useSessionChannel` calls `open(payload)` here.
 *   2. The `loomkin orchestration tour` CLI subcommand, which opens the
 *      same overlay with locally-mirrored phase + persona data.
 *
 * The store is intentionally tiny: a single boolean and the payload. The
 * component (`OnboardingTour`) reads both and renders the rich walkthrough.
 */

export interface TourPhase {
  phase: string;
  name: string;
  icon: string;
  role_blurb?: string;
}

export interface TourPersona {
  key: string;
  name: string;
  icon: string;
  role_blurb?: string;
}

export interface TourPayload {
  phases: TourPhase[];
  personas: TourPersona[];
  /**
   * When `true`, dismissing the overlay should push `mark_tour_seen` to
   * the server (i.e. this was a first-time auto-open). The static
   * `loomkin orchestration tour` invocation sets this `false` because
   * the user is already viewing the tour on purpose.
   */
  mark_seen_on_close: boolean;
}

export interface TourState {
  open: boolean;
  payload: TourPayload | null;
  /** Open the overlay with the given payload. */
  openTour: (payload: TourPayload) => void;
  /** Close the overlay (does not itself send mark_tour_seen). */
  close: () => void;
  /** Test/debug helper — wipe state. */
  reset: () => void;
}

export const useTourStore = create<TourState>((set) => ({
  open: false,
  payload: null,

  openTour: (payload) => set({ open: true, payload }),
  close: () => set({ open: false }),
  reset: () => set({ open: false, payload: null }),
}));
