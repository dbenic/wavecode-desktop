/**
 * App shell. The layout is:
 *
 *   ┌──────────────────────────────────────────────┐
 *   │ Native macOS title bar (provided by Tauri)   │
 *   ├────────────┬─────────────────────────────────┤
 *   │            │  Header strip (agent + status)  │
 *   │  Sidebar   ├─────────────────────────────────┤
 *   │  (agents,  │                                 │
 *   │  artifacts)│   Terminal (xterm.js, attached  │
 *   │            │   to a tmux session on the      │
 *   │            │   remote server via SSH PTY)    │
 *   └────────────┴─────────────────────────────────┘
 *
 * The terminal area is the work surface; the sidebar is additive chrome.
 * Drag-drop anywhere in the window uploads to the active agent.
 */

import { Sidebar } from './components/Sidebar';
import { TerminalView } from './components/TerminalView';
import { HeaderStrip } from './components/HeaderStrip';
import { DropOverlay } from './components/DropOverlay';
import { ConnectionGate } from './components/ConnectionGate';

export default function App() {
  return (
    <ConnectionGate>
      <div className="flex h-full w-full bg-wave-bg text-slate-100">
        <Sidebar />
        <main className="flex-1 flex flex-col min-w-0">
          <HeaderStrip />
          <TerminalView />
        </main>
        <DropOverlay />
      </div>
    </ConnectionGate>
  );
}
