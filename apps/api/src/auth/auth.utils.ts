import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
} from 'crypto';

export const REFRESH_COOKIE_NAME = 'lambkin_refresh_token';

export const REFRESH_TOKEN_TTL_MS =
  30 * 24 * 60 * 60 * 1000;

export function generateRefreshToken(): string {
  return randomBytes(48).toString('hex');
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function generateAuthCode(): string {
  return randomInt(100000, 1000000).toString();
}

export function hashAuthCode(
  tokenId: number,
  code: string,
  secret: string,
): string {
  return createHmac('sha256', secret)
    .update(`${tokenId}:${code}`)
    .digest('hex');
}