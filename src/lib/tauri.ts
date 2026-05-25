/**
 * Thin wrapper over Tauri's invoke + event API so the rest of the app
 * doesn't depend on the SDK shape. Also centralises type-safe command
 * signatures — if the Rust command changes, the TS error is immediate
 * and points here.
 */

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type { ServerProfile } from '../types/api';

export type ConnectionStatus =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'error';

export interface PtyDataEvent {
  pty_id: number;
  data_b64: string;
}

export interface PtyClosedEvent {
  pty_id: number;
  exit_status: number | null;
}

export const tauri = {
  /** Sanity check the bridge. */
  ping(): Promise<string> {
    return invoke<string>('ping');
  },

  /** Open the SSH connection to a server profile. */
  sshConnect(profile: ServerProfileForRust): Promise<ConnectionStatus> {
    return invoke<ConnectionStatus>('ssh_connect', { profile });
  },

  /** Drop the current SSH connection. */
  sshDisconnect(): Promise<void> {
    return invoke('ssh_disconnect');
  },

  /** Open a PTY running `command` and return its id. */
  ptyOpen(opts: { cols: number; rows: number; command: string }): Promise<number> {
    return invoke<number>('pty_open', opts);
  },

  /** Send keystrokes (base64-encoded bytes) to a PTY. */
  ptyWrite(opts: { pty_id: number; data_b64: string }): Promise<void> {
    return invoke('pty_write', opts);
  },

  /** Tell the remote PTY about a new terminal size. */
  ptyResize(opts: { pty_id: number; cols: number; rows: number }): Promise<void> {
    return invoke('pty_resize', opts);
  },

  /** Close a PTY. */
  ptyClose(opts: { pty_id: number }): Promise<void> {
    return invoke('pty_close', opts);
  },

  /** Subscribe to PTY data events. Returns the unlisten function. */
  onPtyData(handler: (e: PtyDataEvent) => void): Promise<UnlistenFn> {
    return listen<PtyDataEvent>('pty:data', (event) => handler(event.payload));
  },

  /** Subscribe to PTY closed events. */
  onPtyClosed(handler: (e: PtyClosedEvent) => void): Promise<UnlistenFn> {
    return listen<PtyClosedEvent>('pty:closed', (event) => handler(event.payload));
  },
};

/**
 * Rust-side ServerProfile shape (snake_case keys). The TS-side
 * `ServerProfile` in `types/api.ts` uses different naming — convert here.
 */
export interface ServerProfileForRust {
  id: string;
  label: string;
  ssh_host: string;
  ssh_user: string | null;
  ssh_port: number | null;
  wavecode_port: number;
  identity_file: string | null;
}

export function toRustProfile(p: ServerProfile): ServerProfileForRust {
  return {
    id: p.id,
    label: p.label,
    ssh_host: p.ssh_host,
    ssh_user: p.ssh_user ?? null,
    ssh_port: p.ssh_port ?? null,
    wavecode_port: p.wavecode_port,
    identity_file: null,
  };
}

/**
 * Base64-encode an ArrayBuffer / Uint8Array for the JSON bridge.
 */
export function bytesToBase64(bytes: Uint8Array): string {
  // btoa expects a binary string of 8-bit chars
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Decode a base64 string to bytes.
 */
export function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}
