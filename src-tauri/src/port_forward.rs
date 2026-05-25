//! TCP port forwarding for the WaveCode HTTP/SSE API.
//!
//! The desktop's React frontend talks to the WaveCode REST + SSE API as if
//! it were at `http://localhost:<dynamic-port>`. Under the hood, that local
//! port is bound by us and forwards over the SSH connection to
//! `localhost:3777` on the server.
//!
//! v0 stub: types only. Real implementation lands week 2.

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct ForwardInfo {
    pub local_port: u16,
    pub remote_port: u16,
}
