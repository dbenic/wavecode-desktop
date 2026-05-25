/**
 * Connection store — holds the active SSH connection profile and the
 * current PTY command (the shell command running in the visible terminal).
 *
 * v0 strategy: hardcode a single profile that uses the host alias "wave"
 * from the user's ~/.ssh/config. Week 1B replaces this with a real
 * profile-management UI + OS keychain storage.
 */

import { create } from 'zustand';
import type { ServerProfile } from '../types/api';
import { ulid } from '../lib/ulid';

const DEFAULT_PROFILE: ServerProfile = {
  id: ulid(),
  label: 'wave (default)',
  ssh_host: 'wave',
  ssh_user: undefined,
  ssh_port: 22,
  wavecode_port: 3777,
};

interface ConnectionState {
  profile: ServerProfile;
  /** Shell command for the active terminal. Null when no terminal is open. */
  ptyCommand: string | null;
  setPtyCommand: (cmd: string | null) => void;
  setProfile: (p: ServerProfile) => void;
}

export const useConnectionStore = create<ConnectionState>((set) => ({
  profile: DEFAULT_PROFILE,
  ptyCommand: null,
  setPtyCommand: (ptyCommand) => set({ ptyCommand }),
  setProfile: (profile) => set({ profile }),
}));
