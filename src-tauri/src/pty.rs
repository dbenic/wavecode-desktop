//! PTY channels over SSH — one per agent terminal view.
//!
//! When the user selects an agent in the sidebar, the frontend invokes
//! `pty_open` which:
//!   1. Opens a russh channel on the active SSH connection
//!   2. Requests a PTY (xterm-256color) and runs `tmux attach -t <session>`
//!   3. Spawns a Tokio task that owns the channel
//!   4. Returns a `pty_id` to the frontend
//!
//! The owning task uses tokio::select! to interleave:
//!   - Incoming messages from the channel (read loop) → emit `pty:data`
//!   - Outgoing commands from the frontend (mpsc channel) → channel.data()
//!     / window_change() / close
//!
//! This single-owner pattern is cleaner than splitting the channel; russh
//! 0.45's `Channel<Msg>` doesn't have a split() that lets us read and
//! write concurrently from separate tasks anyway.

use crate::ssh::{ConnectionState, SshError};
use russh::ChannelMsg;
use serde::Serialize;
use std::collections::HashMap;
use std::io::Cursor;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::{mpsc, Mutex};
use tracing::{debug, info, warn};

/// Frontend-facing identifier for an open PTY. Monotonically increasing,
/// never reused.
pub type PtyId = u64;

/// Sent to the frontend each time the remote side writes bytes. Base64 so
/// arbitrary binary (ANSI/UTF-8) survives the JSON bridge.
#[derive(Debug, Clone, Serialize)]
pub struct PtyDataEvent {
    pub pty_id: PtyId,
    pub data_b64: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PtyClosedEvent {
    pub pty_id: PtyId,
    pub exit_status: Option<u32>,
}

/// Commands the owning task accepts. Sent from Tauri command handlers via mpsc.
enum PtyCommand {
    Write(Vec<u8>),
    Resize { cols: u32, rows: u32 },
    Close,
}

/// Handle held in the registry — lets command handlers send to the
/// owning task, regardless of which task is calling.
pub struct PtyHandle {
    cmd_tx: mpsc::Sender<PtyCommand>,
}

#[derive(Default)]
pub struct PtyRegistry {
    next_id: Mutex<PtyId>,
    ptys: Mutex<HashMap<PtyId, PtyHandle>>,
}

impl PtyRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    async fn next_id(&self) -> PtyId {
        let mut id = self.next_id.lock().await;
        *id += 1;
        *id
    }

    /// Open a PTY running `command` on the active SSH connection.
    pub async fn open(
        self: &Arc<Self>,
        app: AppHandle,
        connection: &ConnectionState,
        cols: u32,
        rows: u32,
        command: String,
    ) -> Result<PtyId, SshError> {
        let guard = connection.session.lock().await;
        let session = guard.as_ref().ok_or(SshError::NotConnected)?;
        let (channel, _channel_id) = session.open_pty_exec(cols, rows, &command).await?;
        drop(guard);

        let pty_id = self.next_id().await;
        info!(pty_id, %command, "pty: opened");

        let (cmd_tx, cmd_rx) = mpsc::channel::<PtyCommand>(64);
        let app_for_task = app.clone();
        let registry_for_task = self.clone();

        tokio::spawn(async move {
            run_pty_task(pty_id, channel, cmd_rx, app_for_task.clone()).await;
            registry_for_task.ptys.lock().await.remove(&pty_id);
            info!(pty_id, "pty: registry entry dropped");
        });

        self.ptys.lock().await.insert(pty_id, PtyHandle { cmd_tx });
        Ok(pty_id)
    }

    pub async fn write(&self, pty_id: PtyId, data: Vec<u8>) -> Result<(), SshError> {
        let ptys = self.ptys.lock().await;
        let handle = ptys.get(&pty_id).ok_or_else(|| {
            SshError::Channel(format!("pty {pty_id} not found (closed?)"))
        })?;
        handle
            .cmd_tx
            .send(PtyCommand::Write(data))
            .await
            .map_err(|e| SshError::Channel(format!("send write: {e}")))?;
        Ok(())
    }

    pub async fn resize(&self, pty_id: PtyId, cols: u32, rows: u32) -> Result<(), SshError> {
        let ptys = self.ptys.lock().await;
        let handle = ptys
            .get(&pty_id)
            .ok_or_else(|| SshError::Channel(format!("pty {pty_id} not found")))?;
        handle
            .cmd_tx
            .send(PtyCommand::Resize { cols, rows })
            .await
            .map_err(|e| SshError::Channel(format!("send resize: {e}")))?;
        Ok(())
    }

    pub async fn close(&self, pty_id: PtyId) -> Result<(), SshError> {
        let ptys = self.ptys.lock().await;
        if let Some(handle) = ptys.get(&pty_id) {
            let _ = handle.cmd_tx.try_send(PtyCommand::Close);
        } else {
            warn!(pty_id, "pty: close called on unknown id");
        }
        Ok(())
    }
}

/// The PTY's owning task. Pumps the channel until close.
async fn run_pty_task(
    pty_id: PtyId,
    mut channel: russh::Channel<russh::client::Msg>,
    mut cmd_rx: mpsc::Receiver<PtyCommand>,
    app: AppHandle,
) {
    let mut exit_status: Option<u32> = None;

    loop {
        tokio::select! {
            biased;
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(PtyCommand::Write(data)) => {
                        let cursor = Cursor::new(data);
                        if let Err(e) = channel.data(cursor).await {
                            warn!(pty_id, error = %e, "pty: write failed");
                        }
                    }
                    Some(PtyCommand::Resize { cols, rows }) => {
                        if let Err(e) = channel.window_change(cols, rows, 0, 0).await {
                            warn!(pty_id, error = %e, "pty: resize failed");
                        }
                    }
                    Some(PtyCommand::Close) | None => {
                        debug!(pty_id, "pty: close requested");
                        break;
                    }
                }
            }
            msg = channel.wait() => {
                match msg {
                    Some(ChannelMsg::Data { data }) => {
                        let b64 = base64_encode(&data);
                        let _ = app.emit("pty:data", PtyDataEvent { pty_id, data_b64: b64 });
                    }
                    Some(ChannelMsg::ExtendedData { data, ext: _ }) => {
                        let b64 = base64_encode(&data);
                        let _ = app.emit("pty:data", PtyDataEvent { pty_id, data_b64: b64 });
                    }
                    Some(ChannelMsg::ExitStatus { exit_status: code }) => {
                        exit_status = Some(code);
                    }
                    Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => {
                        debug!(pty_id, "pty: channel ended");
                        break;
                    }
                    Some(other) => {
                        debug!(pty_id, ?other, "pty: unhandled channel message");
                    }
                }
            }
        }
    }

    // Best-effort close; channel may already be closed.
    let _ = channel.close().await;
    let _ = app.emit(
        "pty:closed",
        PtyClosedEvent {
            pty_id,
            exit_status,
        },
    );
    info!(pty_id, ?exit_status, "pty: closed");
}

/// Minimal RFC 4648 base64 encoder — inlined to avoid adding `base64`
/// just for one function. Standard alphabet, no line breaks.
fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(((bytes.len() + 2) / 3) * 4);
    let mut i = 0;
    while i + 3 <= bytes.len() {
        let n = ((bytes[i] as u32) << 16)
            | ((bytes[i + 1] as u32) << 8)
            | (bytes[i + 2] as u32);
        out.push(TABLE[((n >> 18) & 0x3F) as usize] as char);
        out.push(TABLE[((n >> 12) & 0x3F) as usize] as char);
        out.push(TABLE[((n >> 6) & 0x3F) as usize] as char);
        out.push(TABLE[(n & 0x3F) as usize] as char);
        i += 3;
    }
    match bytes.len() - i {
        0 => {}
        1 => {
            let n = (bytes[i] as u32) << 16;
            out.push(TABLE[((n >> 18) & 0x3F) as usize] as char);
            out.push(TABLE[((n >> 12) & 0x3F) as usize] as char);
            out.push('=');
            out.push('=');
        }
        2 => {
            let n = ((bytes[i] as u32) << 16) | ((bytes[i + 1] as u32) << 8);
            out.push(TABLE[((n >> 18) & 0x3F) as usize] as char);
            out.push(TABLE[((n >> 12) & 0x3F) as usize] as char);
            out.push(TABLE[((n >> 6) & 0x3F) as usize] as char);
            out.push('=');
        }
        _ => unreachable!(),
    }
    out
}

#[cfg(test)]
mod tests {
    use super::base64_encode;

    #[test]
    fn base64_matches_standard_examples() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }
}
