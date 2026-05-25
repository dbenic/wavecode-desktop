//! Tauri command bridge — every function callable from the React frontend
//! via `invoke(...)` lives here.
//!
//! Rules:
//!   - Every command is `async` and returns `Result<T, String>` so errors
//!     surface as JS exceptions / toasts.
//!   - Commands NEVER mutate server state directly — they delegate to the
//!     SSH connection (which then makes HTTP calls or SSH operations).
//!   - Keep this file thin: it's a façade. Logic belongs in the other
//!     modules.

use crate::ssh::{ServerProfile, SshConnection};

/// Sanity-check command — exists so the JS side can verify the bridge is
/// alive before doing real work. Kept as the simplest possible round trip.
#[tauri::command]
pub fn ping() -> &'static str {
    "pong"
}

/// Attempt an SSH connection to the given profile. Returns Ok on success,
/// or a human-readable error string on failure. The frontend uses this in
/// the "Test connection" button on the server-profile form.
#[tauri::command]
pub async fn ssh_test_connection(profile: ServerProfile) -> Result<String, String> {
    let mut conn = SshConnection::new(profile);
    conn.connect().await.map_err(|e| e.to_string())?;
    Ok("ok (stub — real handshake lands week 1)".to_string())
}
