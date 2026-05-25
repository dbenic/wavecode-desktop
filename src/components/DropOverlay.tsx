/**
 * Drag-drop overlay — the hero feature. The whole window is a drop target.
 *
 * v0: shows the overlay when a drag enters. v1 (week 3): wires Tauri's
 * file-drop event to the SFTP channel + artifact API + tmux send-keys.
 */

import { useEffect, useState } from 'react';
import { useUiStore } from '../stores/ui';

export function DropOverlay() {
  const [dragging, setDragging] = useState(false);
  const activeAgentId = useUiStore((s) => s.activeAgentId);

  useEffect(() => {
    const onDragEnter = (e: DragEvent) => {
      e.preventDefault();
      setDragging(true);
    };
    const onDragLeave = (e: DragEvent) => {
      // only hide if leaving the window
      if (e.relatedTarget === null) setDragging(false);
    };
    const onDrop = (e: DragEvent) => {
      e.preventDefault();
      setDragging(false);
      // TODO week 3: hand off files to Tauri command → SFTP upload
    };
    const onDragOver = (e: DragEvent) => e.preventDefault();

    window.addEventListener('dragenter', onDragEnter);
    window.addEventListener('dragleave', onDragLeave);
    window.addEventListener('drop', onDrop);
    window.addEventListener('dragover', onDragOver);
    return () => {
      window.removeEventListener('dragenter', onDragEnter);
      window.removeEventListener('dragleave', onDragLeave);
      window.removeEventListener('drop', onDrop);
      window.removeEventListener('dragover', onDragOver);
    };
  }, []);

  if (!dragging) return null;

  return (
    <div className="fixed inset-0 z-50 bg-slate-950/60 backdrop-blur-sm pointer-events-none flex items-center justify-center border-4 border-emerald-500 transition-opacity">
      <div className="text-center">
        <div className="text-2xl font-semibold text-emerald-400">Drop to upload</div>
        <div className="mt-2 text-sm text-slate-400 font-mono">
          {activeAgentId ? `→ agent ${activeAgentId}` : 'select an agent first'}
        </div>
      </div>
    </div>
  );
}
