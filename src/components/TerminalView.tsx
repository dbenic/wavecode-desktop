/**
 * Embeds xterm.js. In v0 this renders a static placeholder. In week 1 it
 * will allocate a PTY channel over the SSH connection and pipe bytes
 * bidirectionally between xterm and the remote tmux session.
 *
 * Critically: we do NOT spawn a local PTY. The PTY lives on the server.
 * The Tauri command bridge (Rust side) sends raw bytes from the SSH
 * channel up to JS, and forwards keystrokes from xterm back down to the
 * channel. xterm is a pure renderer here.
 */

import { useEffect, useRef } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import { useUiStore } from '../stores/ui';

export function TerminalView() {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const activeAgentId = useUiStore((s) => s.activeAgentId);

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

    termRef.current = term;
    fitRef.current = fit;

    // v0 placeholder content
    term.writeln('\x1b[1;90m[WaveCode Desktop v0]\x1b[0m');
    term.writeln('\x1b[90m  SSH connection layer not yet wired.\x1b[0m');
    term.writeln('\x1b[90m  Week 1 milestone: render a real tmux session via russh PTY.\x1b[0m');
    term.writeln('');

    const handleResize = () => fit.fit();
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      term.dispose();
    };
  }, []);

  // When the active agent changes, switch the PTY (week 2 work — stub for now)
  useEffect(() => {
    const term = termRef.current;
    if (!term || !activeAgentId) return;
    term.writeln(`\x1b[90m  → switched to agent ${activeAgentId} (PTY swap not yet wired)\x1b[0m`);
  }, [activeAgentId]);

  return (
    <div className="flex-1 bg-wave-terminal p-3 min-h-0">
      <div ref={containerRef} className="h-full w-full" />
    </div>
  );
}
