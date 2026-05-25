//! Tauri command bridge — every function callable from the React frontend
//! via `invoke(...)` lives here.
//!
//! Rules:
//!   - Every command is `async` and returns `Result<T, String>` so errors
//!     surface as JS exceptions.
//!   - Commands never mutate server state directly — they delegate to the
//!     SSH connection or registries.
//!   - Keep this file thin: it's a façade. Logic belongs in `ssh.rs`,
//!     `pty.rs`, etc.

use crate::pty::{PtyId, PtyRegistry};
use crate::ssh::{ConnectionState, ConnectionStatus, ServerProfile};
use std::sync::Arc;
use tauri::{AppHandle, State};

#[tauri::command]
pub fn ping() -> &'static str {
    "pong"
}

/// Connect to a server profile. Replaces any existing connection.
#[tauri::command]
pub async fn ssh_connect(
    profile: ServerProfile,
    state: State<'_, ConnectionState>,
) -> Result<ConnectionStatus, String> {
    state.connect(profile).await.map_err(|e| e.to_string())?;
    Ok(ConnectionStatus::Connected)
}

/// Drop the active SSH connection.
#[tauri::command]
pub async fn ssh_disconnect(state: State<'_, ConnectionState>) -> Result<(), String> {
    state.disconnect().await.map_err(|e| e.to_string())
}

/// Open a PTY on the active SSH connection. `command` is the shell
/// command to run inside the PTY — typically `tmux attach -t <session>`.
/// Returns a `pty_id` used for subsequent write/resize/close calls.
///
/// While the PTY is alive, `pty:data` events stream incoming bytes (b64).
/// When the channel closes, a `pty:closed` event is emitted.
#[tauri::command]
pub async fn pty_open(
    app: AppHandle,
    cols: u32,
    rows: u32,
    command: String,
    ssh: State<'_, ConnectionState>,
    registry: State<'_, Arc<PtyRegistry>>,
) -> Result<PtyId, String> {
    registry
        .open(app, &ssh, cols, rows, command)
        .await
        .map_err(|e| e.to_string())
}

/// Send raw bytes (typically a keystroke from xterm.js) to a PTY.
/// `data_b64` lets us safely carry binary across the JSON bridge.
#[tauri::command]
pub async fn pty_write(
    pty_id: PtyId,
    data_b64: String,
    registry: State<'_, Arc<PtyRegistry>>,
) -> Result<(), String> {
    let bytes = base64_decode(&data_b64).map_err(|e| format!("bad base64: {e}"))?;
    registry.write(pty_id, bytes).await.map_err(|e| e.to_string())
}

/// Inform the remote PTY of a new terminal size — called when the xterm
/// container is resized.
#[tauri::command]
pub async fn pty_resize(
    pty_id: PtyId,
    cols: u32,
    rows: u32,
    registry: State<'_, Arc<PtyRegistry>>,
) -> Result<(), String> {
    registry
        .resize(pty_id, cols, rows)
        .await
        .map_err(|e| e.to_string())
}

/// Close a PTY. The reader task exits, the channel closes, the registry
/// drops the entry.
#[tauri::command]
pub async fn pty_close(
    pty_id: PtyId,
    registry: State<'_, Arc<PtyRegistry>>,
) -> Result<(), String> {
    registry.close(pty_id).await.map_err(|e| e.to_string())
}

/// Minimal RFC 4648 base64 decoder — inlined to avoid adding `base64`
/// just for the JS bridge.
fn base64_decode(s: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u32;
    for c in s.bytes() {
        let v: u32 = match c {
            b'A'..=b'Z' => (c - b'A') as u32,
            b'a'..=b'z' => (c - b'a' + 26) as u32,
            b'0'..=b'9' => (c - b'0' + 52) as u32,
            b'+' => 62,
            b'/' => 63,
            b'=' => break,
            b' ' | b'\n' | b'\r' | b'\t' => continue,
            other => return Err(format!("invalid base64 byte 0x{other:02x}")),
        };
        buf = (buf << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8 & 0xFF);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::base64_decode;

    #[test]
    fn base64_decode_roundtrip() {
        assert_eq!(base64_decode("").unwrap(), b"");
        assert_eq!(base64_decode("Zg==").unwrap(), b"f");
        assert_eq!(base64_decode("Zm8=").unwrap(), b"fo");
        assert_eq!(base64_decode("Zm9v").unwrap(), b"foo");
        assert_eq!(base64_decode("Zm9vYmFy").unwrap(), b"foobar");
    }
}
