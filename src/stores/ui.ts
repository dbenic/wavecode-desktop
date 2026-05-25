/**
 * UI-only Zustand store. Server state is NEVER cached here — it lives on
 * the server and arrives via SSE. This store holds only "what the user is
 * currently looking at" and similar transient prefs.
 */

import { create } from 'zustand';

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting' | 'error';

interface UiState {
  // Which agent is currently shown in the terminal view
  activeAgentId: string | null;
  setActiveAgent: (id: string | null) => void;

  // Sidebar visibility
  sidebarCollapsed: boolean;
  toggleSidebar: () => void;

  // SSH connection status to the active server
  connectionStatus: ConnectionStatus;
  setConnectionStatus: (s: ConnectionStatus) => void;
  connectionError: string | null;
  setConnectionError: (e: string | null) => void;

  // Which server profile is active
  activeServerId: string | null;
  setActiveServer: (id: string | null) => void;

  // Palette open/close
  paletteOpen: boolean;
  setPaletteOpen: (open: boolean) => void;
}

export const useUiStore = create<UiState>((set) => ({
  activeAgentId: null,
  setActiveAgent: (id) => set({ activeAgentId: id }),

  sidebarCollapsed: false,
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),

  connectionStatus: 'disconnected',
  setConnectionStatus: (connectionStatus) => set({ connectionStatus }),
  connectionError: null,
  setConnectionError: (connectionError) => set({ connectionError }),

  activeServerId: null,
  setActiveServer: (id) => set({ activeServerId: id }),

  paletteOpen: false,
  setPaletteOpen: (paletteOpen) => set({ paletteOpen }),
}));
