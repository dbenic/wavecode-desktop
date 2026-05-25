//! SSH connection layer — the foundation of everything.
//!
//! One process-wide SSH connection per active server profile. The connection
//! multiplexes PTY channels (for tmux attach), TCP forwards (for the
//! WaveCode HTTP/SSE API), and SFTP (for file uploads). This module owns
//! the connection state and exposes a small Tauri-friendly surface for
//! opening channels.
//!
//! v0 (week 1) — Phase A: real russh handshake + keyfile auth.
//! Multiplexed PTY channels work; port-forward and SFTP land in weeks 2-3.

use async_trait::async_trait;
use russh::client::{self, Handle, Handler, Msg};
use russh::keys::key::{KeyPair, PublicKey};
use russh::keys::load_secret_key;
use russh::{Channel, ChannelId};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{info, warn};

/// User-configured server profile. Persisted client-side; never sent to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerProfile {
    pub id: String,
    pub label: String,
    pub ssh_host: String,
    pub ssh_user: Option<String>,
    pub ssh_port: Option<u16>,
    /// Server-side WaveCode HTTP port. Default 3777.
    pub wavecode_port: u16,
    /// Optional explicit private key path. If unset we try default key
    /// locations under `~/.ssh/`.
    pub identity_file: Option<String>,
}

impl ServerProfile {
    pub fn port(&self) -> u16 {
        self.ssh_port.unwrap_or(22)
    }
    pub fn user(&self) -> String {
        self.ssh_user
            .clone()
            .or_else(|| std::env::var("USER").ok())
            .unwrap_or_else(|| "root".to_string())
    }
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
    #[error("ssh connection failed: {0}")]
    Connection(String),
    #[error("authentication failed: {0}")]
    Auth(String),
    #[error("channel error: {0}")]
    Channel(String),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("not connected")]
    NotConnected,
}

/// Minimal russh client handler. v0: trust on first use (always accept the
/// server key). Future: load `~/.ssh/known_hosts` and prompt on mismatch.
pub struct WaveClient;

#[async_trait]
impl Handler for WaveClient {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &PublicKey,
    ) -> Result<bool, Self::Error> {
        // TODO(security): validate against ~/.ssh/known_hosts
        Ok(true)
    }
}

/// Active SSH session — wraps a russh `Handle` and lets us open channels.
pub struct SshSession {
    pub profile: ServerProfile,
    pub handle: Handle<WaveClient>,
}

impl SshSession {
    /// Open a PTY channel and run a command on it. Returns the russh
    /// Channel + its id, which the caller uses to pump data and dispatch
    /// keystrokes / resize events.
    pub async fn open_pty_exec(
        &self,
        cols: u32,
        rows: u32,
        command: &str,
    ) -> Result<(Channel<Msg>, ChannelId), SshError> {
        let channel = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| SshError::Channel(e.to_string()))?;
        let id = channel.id();

        channel
            .request_pty(true, "xterm-256color", cols, rows, 0, 0, &[])
            .await
            .map_err(|e| SshError::Channel(format!("pty request: {e}")))?;

        channel
            .exec(true, command)
            .await
            .map_err(|e| SshError::Channel(format!("exec: {e}")))?;

        Ok((channel, id))
    }
}

/// Connection state shared across the Tauri app. Held in `tauri::State`.
#[derive(Default)]
pub struct ConnectionState {
    pub session: Mutex<Option<SshSession>>,
}

impl ConnectionState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Establish the SSH session. Replaces any existing session.
    pub async fn connect(&self, profile: ServerProfile) -> Result<(), SshError> {
        info!(host = %profile.ssh_host, port = profile.port(), "ssh: connecting");

        let config = Arc::new(client::Config {
            inactivity_timeout: Some(Duration::from_secs(60)),
            ..client::Config::default()
        });

        let addr = format!("{}:{}", profile.ssh_host, profile.port());
        let mut handle = client::connect(config, addr.as_str(), WaveClient)
            .await
            .map_err(|e| SshError::Connection(e.to_string()))?;

        // Auth: explicit identity_file first, then default ~/.ssh/ keys.
        // ssh-agent integration is TODO for week 1B.
        let user = profile.user();
        let authed =
            try_authenticate(&mut handle, &user, profile.identity_file.as_deref()).await?;

        if !authed {
            return Err(SshError::Auth(
                "no usable credentials (identity_file or ~/.ssh/id_{ed25519,rsa,ecdsa})".into(),
            ));
        }

        info!("ssh: authenticated as {user}");
        let session = SshSession { profile, handle };
        *self.session.lock().await = Some(session);
        Ok(())
    }

    pub async fn disconnect(&self) -> Result<(), SshError> {
        let mut guard = self.session.lock().await;
        if let Some(s) = guard.take() {
            // Best effort — ignore errors.
            let _ = s
                .handle
                .disconnect(russh::Disconnect::ByApplication, "bye", "")
                .await;
        }
        Ok(())
    }
}

/// Walk our preferred auth chain. Returns true on first success.
async fn try_authenticate(
    handle: &mut Handle<WaveClient>,
    user: &str,
    explicit_key: Option<&str>,
) -> Result<bool, SshError> {
    if let Some(path) = explicit_key {
        if try_keyfile(handle, user, path.into()).await? {
            return Ok(true);
        }
    }

    if let Some(home) = dirs::home_dir() {
        for name in ["id_ed25519", "id_rsa", "id_ecdsa"] {
            let path = home.join(".ssh").join(name);
            if path.exists() && try_keyfile(handle, user, path).await? {
                return Ok(true);
            }
        }
    }

    Ok(false)
}

async fn try_keyfile(
    handle: &mut Handle<WaveClient>,
    user: &str,
    path: PathBuf,
) -> Result<bool, SshError> {
    let key: KeyPair = match load_secret_key(&path, None) {
        Ok(k) => k,
        Err(e) => {
            warn!(?path, error = %e, "ssh: skipping unreadable key");
            return Ok(false);
        }
    };

    match handle.authenticate_publickey(user, Arc::new(key)).await {
        Ok(true) => {
            info!(?path, "ssh: authenticated via keyfile");
            Ok(true)
        }
        Ok(false) => {
            warn!(?path, "ssh: keyfile rejected by server");
            Ok(false)
        }
        Err(e) => {
            warn!(?path, error = %e, "ssh: keyfile auth error");
            Ok(false)
        }
    }
}
