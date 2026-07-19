const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function normalizeRoomCode(rawCode: string): string {
  const code = rawCode.replace(/\s+/g, "").toUpperCase();

  if (!/^[A-Z0-9]{4,12}$/.test(code)) {
    throw new Error("Invalid room code");
  }

  return code;
}

export function createRoomCode(random: () => number = Math.random): string {
  let code = "";

  for (let index = 0; index < 6; index += 1) {
    const alphabetIndex = Math.floor(random() * ROOM_CODE_ALPHABET.length);
    code += ROOM_CODE_ALPHABET[Math.min(alphabetIndex, ROOM_CODE_ALPHABET.length - 1)];
  }

  return code;
}
