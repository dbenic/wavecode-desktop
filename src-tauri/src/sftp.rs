//! SFTP file uploads — used by drag-drop to land files in agent workspaces
//! as WaveCode artifacts.
//!
//! Flow:
//!   1. User drags a file/screenshot onto the app window
//!   2. JS side fires a Tauri command with the file paths + active agent
//!   3. We SFTP the bytes to a staging dir on the server
//!   4. We POST to `/api/artifacts/upload` (via the port-forwarded HTTP)
//!      to register it and (optionally) attach it to the agent
//!   5. We send a `tmux send-keys` to inject the artifact path at the
//!      cursor of the active tmux pane
//!
//! v0 stub. Real implementation lands week 3.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadRequest {
    pub agent_id: String,
    pub local_paths: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct UploadResult {
    pub artifact_ids: Vec<String>,
    pub injected_paths: Vec<String>,
}
