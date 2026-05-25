/**
 * usePtyChannel — opens a PTY on the active SSH connection and wires
 * bidirectional I/O between it and an xterm.js Terminal instance.
 *
 * Lifecycle:
 *   - Caller passes a `Terminal` (or null) and a `command` (or null).
 *   - When both are non-null, we call `pty_open` and start listening
 *     for `pty:data` events, writing them into the terminal.
 *   - xterm's `onData` is forwarded to `pty_write`.
 *   - xterm's `onResize` is forwarded to `pty_resize`.
 *   - On unmount / command change / terminal change, we `pty_close`
 *     and unsubscribe.
 */

import { useEffect, useRef } from 'react';
import type { Terminal } from '@xterm/xterm';
import { base64ToBytes, bytesToBase64, tauri } from '../lib/tauri';

interface UsePtyChannelOpts {
  terminal: Terminal | null;
  /** Shell command to run inside the PTY, e.g. `tmux attach -t wc-cl-backend`. */
  command: string | null;
}

export function usePtyChannel({ terminal, command }: UsePtyChannelOpts): void {
  const ptyIdRef = useRef<number | null>(null);

  useEffect(() => {
    if (!terminal || !command) return;
    let cancelled = false;
    let unlistenData: (() => void) | null = null;
    let unlistenClosed: (() => void) | null = null;
    let onDataDispose: { dispose(): void } | null = null;
    let onResizeDispose: { dispose(): void } | null = null;

    const cols = terminal.cols;
    const rows = terminal.rows;

    (async () => {
      try {
        const id = await tauri.ptyOpen({ cols, rows, command });
        if (cancelled) {
          await tauri.ptyClose({ pty_id: id }).catch(() => {});
          return;
        }
        ptyIdRef.current = id;

        unlistenData = await tauri.onPtyData((e) => {
          if (e.pty_id !== id) return;
          const bytes = base64ToBytes(e.data_b64);
          terminal.write(bytes);
        });

        unlistenClosed = await tauri.onPtyClosed((e) => {
          if (e.pty_id !== id) return;
          terminal.writeln(
            `\r\n\x1b[90m[pty closed: exit=${e.exit_status ?? 'unknown'}]\x1b[0m`,
          );
        });

        onDataDispose = terminal.onData((data) => {
          const bytes = new TextEncoder().encode(data);
          tauri
            .ptyWrite({ pty_id: id, data_b64: bytesToBase64(bytes) })
            .catch((err) => {
              console.error('pty_write failed', err);
            });
        });

        onResizeDispose = terminal.onResize(({ cols: c, rows: r }) => {
          tauri.ptyResize({ pty_id: id, cols: c, rows: r }).catch((err) => {
            console.error('pty_resize failed', err);
          });
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!cancelled && terminal) {
          terminal.writeln(`\r\n\x1b[31m[pty open failed: ${msg}]\x1b[0m`);
        }
      }
    })();

    return () => {
      cancelled = true;
      unlistenData?.();
      unlistenClosed?.();
      onDataDispose?.dispose();
      onResizeDispose?.dispose();
      const id = ptyIdRef.current;
      ptyIdRef.current = null;
      if (id !== null) {
        tauri.ptyClose({ pty_id: id }).catch(() => {});
      }
    };
  }, [terminal, command]);
}
