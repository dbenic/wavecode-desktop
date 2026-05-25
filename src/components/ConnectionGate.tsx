/**
 * Wraps the app in a connection lifecycle. v0 stub: just renders children.
 * Future: blocks the app on first-run if no server profile is configured,
 * shows a "Connect to server" splash, handles auth errors, etc.
 */

import type { ReactNode } from 'react';

export function ConnectionGate({ children }: { children: ReactNode }) {
  return <>{children}</>;
}
