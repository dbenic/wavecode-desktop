/**
 * Hand-copied API types from WaveCode core.
 *
 * v0 strategy: keep these in sync manually. Source of truth is
 * `wavecode/docs/api.md` and the actual server response shapes.
 *
 * v1+ strategy: replace with a published `@wavecode/api-types` package
 * generated from the core repo so updates land via dependency bump.
 */

export type AgentStatus = 'idle' | 'working' | 'error';
export type AgentMode = 'adopted' | 'spawned';
export type AgentRuntime = 'claude-code' | 'codex' | 'aider' | string;

export interface Agent {
  id: string;
  name: string;
  runtime: AgentRuntime;
  tmux_session: string;
  workspace: string | null;
  mode: AgentMode;
  status: AgentStatus;
  created_at: string;
}

export interface Task {
  id: string;
  agent_id: string | null;
  prompt: string;
  status: 'pending' | 'running' | 'done' | 'failed' | 'blocked';
  priority: number;
  created_at: string;
}

export interface Artifact {
  id: string;
  filename: string;
  mime_type: string;
  sha256: string;
  size_bytes: number;
  storage_path: string;
  preview_path: string | null;
  source_agent_id: string | null;
  source_run_id: string | null;
  note: string | null;
  created_at: string;
}

/**
 * Server-Sent Events surface. The desktop subscribes to /api/events and
 * pattern-matches on `type` to update the local UI state.
 */
export interface AgentOutputPayload {
  lastOutputLine: string;
  permissionMode: string | null;
  outputVersion: number;
  outputUpdatedAt: string;
}

export type ServerEvent =
  | { type: 'agent.spawned'; entity_id: string; payload: Agent }
  | { type: 'agent.killed'; entity_id: string; payload: { id: string } }
  | {
      type: 'agent.status_changed';
      entity_id: string;
      payload: AgentOutputPayload & { status: AgentStatus; autoCorrect?: boolean };
    }
  /**
   * The agent's tmux pane produced new output without a status change. The
   * desktop sidebar uses this to flash a "this agent just spoke" indicator.
   * No polling required.
   */
  | { type: 'agent.output_updated'; entity_id: string; payload: AgentOutputPayload }
  | { type: 'task.created'; entity_id: string; payload: Task }
  | { type: 'task.completed'; entity_id: string; payload: { task_id: string; success: boolean } }
  | { type: 'run.started'; entity_id: string; payload: { run_id: string; agent_id: string } }
  | {
      type: 'run.finished';
      entity_id: string;
      payload: { run_id: string; exit_code: number; duration_s?: number; changed_files?: string[] };
    }
  | { type: 'run.failed'; entity_id: string; payload: { run_id: string; error: string } }
  | { type: 'artifact.created'; entity_id: string; payload: Artifact }
  | { type: 'artifact.deleted'; entity_id: string; payload: { id: string; filename: string; sha256: string } }
  | { type: 'artifact.detached'; entity_id: string; payload: { agent_id: string; filename: string } }
  | { type: 'heartbeat'; entity_id: string; payload: Record<string, never> };

/**
 * Local-only types — describe the SSH connection profile the desktop holds.
 * Never sent to the server.
 */
export interface ServerProfile {
  id: string;          // local ulid
  label: string;       // user-facing name, e.g. "wave (personal)"
  ssh_host: string;    // either ~/.ssh/config alias or raw host
  ssh_user?: string;   // optional override
  ssh_port?: number;   // default 22
  wavecode_port: number; // server-side HTTP port, default 3777
  token?: string;      // optional bearer token, stored in OS keychain
}
