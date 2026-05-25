//! WaveCode Desktop — Tauri shell.
//!
//! See `CLAUDE.md` for the non-negotiable architectural constraints. The
//! short version: this app is an SSH client to a remote WaveCode server.
//! No local agents, no local LLM calls, no local mode of any kind.
//!
//! Module layout:
//!   - [`ssh`]          single SSH connection (russh) + auth chain
//!   - [`pty`]          PTY channel registry — one per agent terminal view
//!   - [`port_forward`] HTTP/SSE tunnel for the WaveCode REST + SSE API (week 2)
//!   - [`sftp`]         drag-drop file uploads (week 3)
//!   - [`commands`]     Tauri command bridge — frontend calls these

mod commands;
mod port_forward;
mod pty;
mod sftp;
mod ssh;

use std::sync::Arc;
use tracing_subscriber::{fmt, EnvFilter};

/// Tauri entry point. Called from `main.rs`.
pub fn run() {
    // Structured logging — controllable via RUST_LOG.
    let _ = fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,russh=warn,russh_keys=warn")),
        )
        .try_init();

    let ssh_state = ssh::ConnectionState::new();
    let pty_registry = Arc::new(pty::PtyRegistry::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(ssh_state)
        .manage(pty_registry)
        .invoke_handler(tauri::generate_handler![
            commands::ping,
            commands::ssh_connect,
            commands::ssh_disconnect,
            commands::pty_open,
            commands::pty_write,
            commands::pty_resize,
            commands::pty_close,
        ])
        .run(tauri::generate_context!())
        .expect("error while running WaveCode Desktop");
}
