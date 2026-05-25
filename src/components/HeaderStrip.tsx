/**
 * Header strip above the terminal — shows the active agent's name,
 * status, elapsed time. Click the agent name to open a quick switcher.
 */

import { useUiStore, type ConnectionStatus } from '../stores/ui';

export function HeaderStrip() {
  const { activeAgentId, connectionStatus } = useUiStore();

  return (
    <header className="h-9 border-b border-slate-800/60 flex items-center px-4 text-sm text-slate-400 shrink-0">
      <div className="flex items-center gap-2">
        <span className="font-mono">{activeAgentId ? `agent ${activeAgentId}` : 'no agent selected'}</span>
      </div>
      <div className="ml-auto flex items-center gap-3 text-xs">
        <ConnectionPill status={connectionStatus} />
      </div>
    </header>
  );
}

function ConnectionPill({ status }: { status: ConnectionStatus }) {
  const label =
    status === 'connected'
      ? 'connected'
      : status === 'connecting'
        ? 'connecting…'
        : status === 'reconnecting'
          ? 'reconnecting…'
          : status === 'error'
            ? 'connection error'
            : 'disconnected';

  const color =
    status === 'connected'
      ? 'text-emerald-400'
      : status === 'connecting' || status === 'reconnecting'
        ? 'text-amber-400'
        : status === 'error'
          ? 'text-red-400'
          : 'text-slate-500';

  return <span className={`uppercase tracking-wider ${color}`}>{label}</span>;
}
