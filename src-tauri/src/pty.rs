//! PTY channels over SSH — one per agent terminal view.
//!
//! When the user selects an agent in the sidebar, we open a PTY channel
//! on the shared SSH connection and run `tmux attach -t <agent_session>`.
//! Bytes from the channel are forwarded to the JS side via a Tauri event,
//! which xterm.js renders. Keystrokes from xterm flow back the other way.
//!
//! v0 stub: types and the channel registry shape. Real implementation
//! lands week 1 alongside `ssh.rs`.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PtySize {
    pub cols: u16,
    pub rows: u16,
}

#[derive(Debug, thiserror::Error)]
pub enum PtyError {
    #[error("no SSH connection")]
    NoConnection,
    #[error("PTY channel error: {0}")]
    Channel(String),
}
