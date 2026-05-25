/**
 * TerminalView — xterm.js attached to a remote PTY via SSH.
 *
 * The PTY lives on the server (NOT on the user's machine). xterm just
 * renders the bytes that flow over the SSH channel. Keystrokes flow back
 * the other way.
 *
 * v0: a small toolbar over the terminal lets the user open one of a few
 * preset shells while we don't yet have the sidebar wired to real agents.
 * Once week 2 lands the SSE-driven agent list, the sidebar selection
 * sets `ptyCommand` directly to `tmux attach -t <session>`.
 */

import { useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import { useUiStore } from '../stores/ui';
import { useConnectionStore } from '../stores/connection';
import { usePtyChannel } from '../hooks/usePtyChannel';

export function TerminalView() {
  const containerRef = useRef<HTMLDivElement>(null);
  const [terminal, setTerminal] = useState<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const activeAgentId = useUiStore((s) => s.activeAgentId);
  const { ptyCommand, setPtyCommand } = useConnectionStore();

  // Mount xterm once per component lifetime.
  useEffect(() => {
    if (!containerRef.current) return;

    const term = new Terminal({
      fontFamily: '"JetBrains Mono", ui-monospace, monospace',
      fontSize: 13,
      lineHeight: 1.4,
      cursorBlink: true,
      cursorStyle: 'block',
      theme: {
        background: '#020617',
        foreground: '#e2e8f0',
        cursor: '#10b981',
        cursorAccent: '#020617',
        selectionBackground: 'rgba(16, 185, 129, 0.25)',
      },
      scrollback: 10_000,
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(containerRef.current);
    fit.fit();
    fitRef.current = fit;

    term.writeln('\x1b[1;92m[WaveCode Desktop — v0]\x1b[0m');
    term.writeln('\x1b[90m  Pick a command above to open a remote shell.\x1b[0m');
    term.writeln('');

    const handleResize = () => {
      try {
        fit.fit();
      } catch {
        /* container has 0 size at startup */
      }
    };
    window.addEventListener('resize', handleResize);

    setTerminal(term);

    return () => {
      window.removeEventListener('resize', handleResize);
      term.dispose();
      setTerminal(null);
    };
  }, []);

  // When activeAgentId changes (week 2 wiring), set the tmux attach command.
  useEffect(() => {
    if (!activeAgentId) return;
    setPtyCommand(`tmux attach -t ${activeAgentId}`);
  }, [activeAgentId, setPtyCommand]);

  // Wire the PTY to the terminal once we have both.
  usePtyChannel({ terminal, command: ptyCommand });

  return (
    <div className="flex-1 bg-wave-terminal flex flex-col min-h-0">
      <PtyToolbar />
      <div className="flex-1 p-3 min-h-0">
        <div ref={containerRef} className="h-full w-full" />
      </div>
    </div>
  );
}

function PtyToolbar() {
  const { ptyCommand, setPtyCommand } = useConnectionStore();

  const presets: { label: string; cmd: string }[] = [
    { label: 'tmux list', cmd: 'tmux ls' },
    { label: 'bash', cmd: 'bash -l' },
    { label: 'htop', cmd: 'htop' },
  ];

  return (
    <div className="border-b border-slate-800/60 px-3 py-1.5 flex items-center gap-2 text-xs">
      <span className="text-slate-500 uppercase tracking-wider mr-1">pty</span>
      {presets.map((p) => (
        <button
          key={p.label}
          onClick={() => setPtyCommand(p.cmd)}
          className={`px-2 py-0.5 rounded font-mono transition-colors ${
            ptyCommand === p.cmd
              ? 'bg-emerald-600/20 text-emerald-300'
              : 'text-slate-500 hover:bg-slate-800/60 hover:text-slate-300'
          }`}
        >
          {p.label}
        </button>
      ))}
      {ptyCommand && (
        <button
          onClick={() => setPtyCommand(null)}
          className="ml-auto px-2 py-0.5 rounded text-slate-500 hover:text-red-400 hover:bg-slate-800/60"
        >
          close pty
        </button>
      )}
    </div>
  );
}
