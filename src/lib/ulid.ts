/**
 * Tiny ULID generator (Crockford-base32, time + 80 bits of random).
 * Inlined to avoid pulling a dependency for one function.
 */

const CHARS = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function ulid(timestamp: number = Date.now()): string {
  let out = '';
  let t = timestamp;
  for (let i = 9; i >= 0; i--) {
    out = CHARS[t % 32] + out;
    t = Math.floor(t / 32);
  }
  for (let i = 0; i < 16; i++) {
    out += CHARS[Math.floor(Math.random() * 32)];
  }
  return out;
}
