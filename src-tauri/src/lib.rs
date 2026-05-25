//! WaveCode Desktop — Tauri shell.
//!
//! See `CLAUDE.md` for the non-negotiable architectural constraints. The
//! short version: this app is an SSH client to a remote WaveCode server.
//! No local agents, no local LLM calls, no local mode of any kind.
//!
//! Module layout:
//!   - [`ssh`]          single SSH connection + reconnect loop (russh)
//!   - [`pty`]          PTY channels for tmux attach (rendered by xterm.js)
//!   - [`port_forward`] HTTP/SSE tunnel for the WaveCode REST + SSE API
//!   - [`sftp`]         drag-drop file uploads to agent workspaces
//!   - [`commands`]     Tauri command bridge — frontend calls these

mod commands;
mod port_forward;
mod pty;
mod sftp;
mod ssh;

use tracing_subscriber::{fmt, EnvFilter};

/// Tauri entry point. Called from `main.rs`.
pub fn run() {
    // Set up structured logging early so SSH connection diagnostics are visible
    let _ = fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info,russh=warn")),
        )
        .try_init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            commands::ping,
            commands::ssh_test_connection,
        ])
        .run(tauri::generate_context!())
        .expect("error while running WaveCode Desktop");
}
