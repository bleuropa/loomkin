import { useSessionStore } from "../stores/sessionStore.js";
import { joinChannel } from "../lib/socket.js";
import type { Channel } from "phoenix";

export function getSessionChannel(): Channel | null {
  const sessionId = useSessionStore.getState().sessionId;
  if (!sessionId) return null;
  return joinChannel(`session:${sessionId}`);
}
