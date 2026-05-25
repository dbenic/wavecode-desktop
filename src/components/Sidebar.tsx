/**
 * Sidebar — agents list (top), artifacts (middle), spawn button (bottom).
 *
 * v0 stub: hard-coded sample data so the layout renders. Wired to the real
 * SSE-driven agent list in week 2.
 */

import { useUiStore } from '../stores/ui';
import type { Agent } from '../types/api';

const SAMPLE_AGENTS: Agent[] = [
  { id: '1', name: 'cl-backend', runtime: 'claude-code', tmux_session: 'wc-cl-backend', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
  { id: '2', name: 'cl-api', runtime: 'claude-code', tmux_session: 'wc-cl-api', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
  { id: '3', name: 'codex-tests', runtime: 'codex', tmux_session: 'wc-codex-tests', workspace: null, mode: 'spawned', status: 'idle', created_at: '' },
  { id: '4', name: 'aider-docs', runtime: 'aider', tmux_session: 'wc-aider-docs', workspace: null, mode: 'spawned', status: 'idle', created_at: '' },
  { id: '5', name: 'reviewer', runtime: 'claude-code', tmux_session: 'wc-reviewer', workspace: null, mode: 'spawned', status: 'working', created_at: '' },
];

export function Sidebar() {
  const { sidebarCollapsed, activeAgentId, setActiveAgent } = useUiStore();

  if (sidebarCollapsed) {
    return (
      <aside className="w-14 border-r border-slate-800/60 flex flex-col items-center py-3 gap-3 shrink-0">
        {SAMPLE_AGENTS.map((a) => (
          <button
            key={a.id}
            onClick={() => setActiveAgent(a.id)}
            className={`w-8 h-8 rounded-md flex items-center justify-center hover:bg-slate-800/50 ${
              activeAgentId === a.id ? 'bg-slate-800' : ''
            }`}
            title={a.name}
          >
            <StatusDot status={a.status} />
          </button>
        ))}
      </aside>
    );
  }

  return (
    <aside className="w-[220px] border-r border-slate-800/60 flex flex-col shrink-0">
      <div className="px-3 pt-3 pb-2">
        <div className="text-[11px] uppercase tracking-wider text-slate-500 font-semibold">
          Agents ({SAMPLE_AGENTS.length})
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-2">
        {SAMPLE_AGENTS.map((a) => (
          <AgentRow
            key={a.id}
            agent={a}
            active={activeAgentId === a.id}
            onClick={() => setActiveAgent(a.id)}
          />
        ))}
      </div>

      <div className="border-t border-slate-800/60 p-2">
        <button className="w-full text-left text-sm text-slate-400 hover:text-slate-200 px-2 py-1.5 rounded hover:bg-slate-800/50">
          ⊕ Spawn agent
          <span className="float-right text-xs text-slate-600">⌘N</span>
        </button>
      </div>
    </aside>
  );
}

function AgentRow({ agent, active, onClick }: { agent: Agent; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`w-full flex items-center gap-2 px-2 py-1.5 rounded text-sm transition-colors ${
        active
          ? 'bg-emerald-500/10 text-slate-100 border-l-2 border-l-emerald-500 -ml-px pl-[7px]'
          : 'text-slate-400 hover:bg-slate-800/50 hover:text-slate-200'
      }`}
    >
      <StatusDot status={agent.status} />
      <span className="font-mono truncate">{agent.name}</span>
    </button>
  );
}

function StatusDot({ status }: { status: Agent['status'] }) {
  const color =
    status === 'working'
      ? 'bg-emerald-500 status-pulse'
      : status === 'error'
        ? 'bg-red-500'
        : 'bg-slate-600';
  return <span className={`w-2 h-2 rounded-full shrink-0 ${color}`} />;
}
