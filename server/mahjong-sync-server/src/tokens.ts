import { createHmac, timingSafeEqual } from "node:crypto";

export interface MemberTokenPayload {
  roomId: string;
  memberId: string;
  deviceId: string;
  exp: number;
}

export function createMemberToken(secret: string, payload: MemberTokenPayload): string {
  const body = toBase64Url(Buffer.from(JSON.stringify(payload), "utf8"));
  const signature = sign(secret, body);

  return `${body}.${signature}`;
}

export function verifyMemberToken(secret: string, token: string | null | undefined): MemberTokenPayload {
  if (!token) {
    throw httpError(401, "Member token is required");
  }

  const [body, signature] = token.split(".");
  if (!body || !signature) {
    throw httpError(401, "Invalid member token");
  }

  const expected = sign(secret, body);
  const expectedBytes = Buffer.from(expected);
  const actualBytes = Buffer.from(signature);

  if (expectedBytes.length !== actualBytes.length || !timingSafeEqual(expectedBytes, actualBytes)) {
    throw httpError(401, "Invalid member token");
  }

  const payload = JSON.parse(fromBase64Url(body).toString("utf8")) as MemberTokenPayload;
  if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) {
    throw httpError(401, "Member token expired");
  }

  return payload;
}

export function httpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function sign(secret: string, body: string): string {
  return toBase64Url(createHmac("sha256", secret).update(body).digest());
}

function toBase64Url(buffer: Buffer): string {
  return buffer.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Buffer {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Buffer.from(padded, "base64");
}
