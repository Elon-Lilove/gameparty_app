import { HttpError } from "./http";
import type { Env, MemberTokenPayload } from "./types";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function toBase64Url(bytes: ArrayBuffer | Uint8Array): string {
  let binary = "";
  const array = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

  for (const byte of array) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

async function signingKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function createMemberToken(env: Env, payload: MemberTokenPayload): Promise<string> {
  const body = toBase64Url(encoder.encode(JSON.stringify(payload)));
  const signature = await crypto.subtle.sign("HMAC", await signingKey(env.MEMBER_TOKEN_SECRET), encoder.encode(body));

  return `${body}.${toBase64Url(signature)}`;
}

export async function verifyMemberToken(env: Env, token: string | null): Promise<MemberTokenPayload> {
  if (!token) {
    throw new HttpError(401, "Member token is required");
  }

  const [body, signature] = token.split(".");

  if (!body || !signature) {
    throw new HttpError(401, "Invalid member token");
  }

  const ok = await crypto.subtle.verify(
    "HMAC",
    await signingKey(env.MEMBER_TOKEN_SECRET),
    fromBase64Url(signature),
    encoder.encode(body),
  );

  if (!ok) {
    throw new HttpError(401, "Invalid member token");
  }

  const payload = JSON.parse(decoder.decode(fromBase64Url(body))) as MemberTokenPayload;

  if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Member token expired");
  }

  return payload;
}

export function readBearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");

  if (!header?.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  return header.slice("bearer ".length).trim();
}
