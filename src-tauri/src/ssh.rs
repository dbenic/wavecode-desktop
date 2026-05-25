//! SSH connection layer — the foundation of everything.
//!
//! One process-wide SSH connection per active server profile. The connection
//! multiplexes:
//!   - PTY channels for tmux attach (one per agent terminal view)
//!   - A TCP forward for the WaveCode HTTP/SSE API
//!   - An SFTP channel for file uploads
//!
//! v0 stub: types and a no-op `connect` so the rest of the app can compile
//! and the Rust ↔ JS bridge can be wired. Real russh implementation lands
//! in week 1.
//!
//! The connection must be **resilient to laptop sleep / network churn**.
//! When the SSH session dies we surface a status change to the frontend and
//! retry with exponential backoff. Tmux sessions on the server keep running
//! while we're disconnected, so re-attaching after reconnect is loss-free.

use serde::{Deserialize, Serialize};

/// A user-configured server profile. The desktop stores a list of these in
/// the OS keychain / config dir. Selecting one triggers a `connect`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerProfile {
    /// Local id (ulid). Stable across renames.
    pub id: String,
    /// User-facing label, e.g. "wave (personal)".
    pub label: String,
    /// Either an `~/.ssh/config` alias or a raw hostname/IP.
    pub ssh_host: String,
    /// Optional user override (defaults to `~/.ssh/config` or current user).
    pub ssh_user: Option<String>,
    /// Optional port override (defaults to 22 or `~/.ssh/config` value).
    pub ssh_port: Option<u16>,
    /// The port the WaveCode daemon listens on, server-side. Default 3777.
    pub wavecode_port: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error,
}

#[derive(Debug, thiserror::Error)]
pub enum SshError {
    #[error("SSH connection failed: {0}")]
    Connection(String),
    #[error("authentication failed: {0}")]
    Auth(String),
    #[error("channel error: {0}")]
    Channel(String),
    #[error("not connected")]
    NotConnected,
}

/// Top-level handle to the SSH connection. Future: owns a russh `Handle`,
/// channel registry, port-forward task, reconnect supervisor.
pub struct SshConnection {
    pub profile: ServerProfile,
    pub status: ConnectionStatus,
}

impl SshConnection {
    /// Construct a connection in the `Disconnected` state. Call `connect`
    /// to actually establish the SSH session.
    pub fn new(profile: ServerProfile) -> Self {
        Self {
            profile,
            status: ConnectionStatus::Disconnected,
        }
    }

    /// Establish the SSH session. v0 stub: returns Ok without doing
    /// anything. Week 1 lands the real russh handshake here.
    pub async fn connect(&mut self) -> Result<(), SshError> {
        tracing::info!(host = %self.profile.ssh_host, "ssh: would connect (stub)");
        self.status = ConnectionStatus::Connecting;
        // TODO(week-1): russh handshake, auth via ssh-agent / keyfile
        // TODO(week-1): start port-forward task (server:wavecode_port → local:?)
        // TODO(week-1): start reconnect supervisor
        Ok(())
    }
}
