/**
 * Agents store — in v0 this is hardcoded sample data so the sidebar can
 * render. Week 2 replaces it with a live feed from the WaveCode core API
 * over the SSH port-forward (the SSE event consumer).
 *
 * The sample data is intentionally NOT useful for real testing; everyone
 * developing against this will have different tmux sessions on their
 * own server. Use the "tmux list" toolbar button to see real sessions,
 * then `bash -l` and `tmux attach -t <real-session-name>` to attach.
 *
 * The store is also where any future "selected agent → tmux session"
 * lookup will live; TerminalView reads from here so it doesn't depend
 * on Sidebar's data shape directly.
 */

import { create } from 'zustand';
import type { Agent } from '../types/api';

const SAMPLE_AGENTS: Agent[] = [
  { id: 'sample-1', name: 'cl-backend', runtime: 'claude-code', tmux_session: 'cl-backend', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
  { id: 'sample-2', name: 'cl-api', runtime: 'claude-code', tmux_session: 'cl-api', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
  { id: 'sample-3', name: 'codex-tests', runtime: 'codex', tmux_session: 'codex-tests', workspace: null, mode: 'spawned', status: 'idle', created_at: '' },
  { id: 'sample-4', name: 'aider-docs', runtime: 'aider', tmux_session: 'aider-docs', workspace: null, mode: 'spawned', status: 'idle', created_at: '' },
  { id: 'sample-5', name: 'reviewer', runtime: 'claude-code', tmux_session: 'reviewer', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
];

interface AgentsState {
  agents: Agent[];
  /** Look up an agent by its id. Returns undefined if unknown. */
  getAgent: (id: string) => Agent | undefined;
}

export const useAgentsStore = create<AgentsState>((_set, get) => ({
  agents: SAMPLE_AGENTS,
  getAgent: (id: string) => get().agents.find((a) => a.id === id),
}));
