/**
 * ConnectionGate — manages the SSH connection lifecycle.
 *
 * v0 strategy:
 *   - On mount, try to connect to the default profile (`wave` from
 *     ~/.ssh/config).
 *   - While connecting / errored, show a status splash with a Connect
 *     button. Don't render children.
 *   - Once connected, render children.
 *
 * Week 1B: replace the splash with a real first-run form (host, user,
 * key path) and persist profiles to OS config.
 */

import { useEffect, useState, type ReactNode } from 'react';
import { useUiStore } from '../stores/ui';
import { useConnectionStore } from '../stores/connection';
import { tauri, toRustProfile } from '../lib/tauri';

export function ConnectionGate({ children }: { children: ReactNode }) {
  const { connectionStatus, setConnectionStatus, connectionError, setConnectionError } = useUiStore();
  const profile = useConnectionStore((s) => s.profile);
  const [attempted, setAttempted] = useState(false);

  useEffect(() => {
    if (attempted) return;
    setAttempted(true);
    void connect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [attempted]);

  async function connect() {
    setConnectionStatus('connecting');
    setConnectionError(null);
    try {
      await tauri.sshConnect(toRustProfile(profile));
      setConnectionStatus('connected');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setConnectionError(msg);
      setConnectionStatus('error');
    }
  }

  if (connectionStatus === 'connected') {
    return <>{children}</>;
  }

  return (
    <div className="h-full w-full flex items-center justify-center bg-wave-bg">
      <div className="max-w-md w-full px-8">
        <div className="flex items-center gap-2 mb-3">
          <span className="w-2 h-2 rounded-full bg-emerald-500" />
          <span className="text-xs uppercase tracking-wider text-slate-400 font-semibold">
            WaveCode Desktop
          </span>
        </div>
        <h1 className="text-xl text-slate-100 font-semibold mb-2">
          Connect to <span className="font-mono text-emerald-400">{profile.ssh_host}</span>
        </h1>
        <p className="text-sm text-slate-400 mb-6">
          {connectionStatus === 'connecting' && 'Authenticating via SSH key…'}
          {connectionStatus === 'error' &&
            'Could not authenticate. Make sure ~/.ssh/config has an entry for this host and the key is present.'}
          {connectionStatus === 'disconnected' && 'Ready to connect.'}
        </p>

        {connectionError && (
          <pre className="text-xs font-mono text-red-400 bg-slate-900/60 border border-slate-800 rounded p-3 mb-4 whitespace-pre-wrap break-all">
            {connectionError}
          </pre>
        )}

        <button
          onClick={connect}
          disabled={connectionStatus === 'connecting'}
          className="w-full bg-emerald-600 hover:bg-emerald-500 disabled:bg-slate-700 disabled:text-slate-500 text-white text-sm font-medium py-2 rounded transition-colors"
        >
          {connectionStatus === 'connecting' ? 'Connecting…' : 'Connect'}
        </button>

        <p className="text-xs text-slate-600 mt-6 leading-relaxed">
          v0 uses a hardcoded profile pointing at <span className="font-mono">wave</span>. Profile
          management UI lands in week 1B. Keys are read from{' '}
          <span className="font-mono">~/.ssh/id_ed25519</span>,{' '}
          <span className="font-mono">id_rsa</span>, or <span className="font-mono">id_ecdsa</span>.
        </p>
      </div>
    </div>
  );
}
