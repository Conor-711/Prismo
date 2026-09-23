import jpeg from "npm:jpeg-js@0.4.4";

export function profileInput(value: any) {
  const invalid = () => { throw new Error("invalid_profile"); };
  if (!value || Array.isArray(value) || Object.keys(value).sort().join() !== "avatar,bio,handle,revision,username") invalid();
  if (![value.username, value.handle, value.bio].every(v => typeof v === "string")) invalid();
  const username = value.username.trim(), handle = value.handle.trim().replace(/^@/, "").toLowerCase(), bio = value.bio.trim();
  if (![...username].length || [...username].length > 28 || /[\u0000-\u001f\u007f]/.test(username) ||
    !/^[a-z][a-z0-9_]{2,23}$/.test(handle) || [...bio].length > 120 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(bio) ||
    !Number.isSafeInteger(value.revision) || value.revision < 0 || value.revision >= 2147483647) invalid();
  const avatar = value.avatar;
  if (!avatar || Array.isArray(avatar) || !["keep", "remove", "provider", "upload"].includes(avatar.action) ||
      Object.keys(avatar).sort().join() !== (avatar.action === "upload" ? "action,jpegBase64" : "action")) invalid();
  let image: Uint8Array | null = null;
  if (avatar.action === "upload") {
    if (typeof avatar.jpegBase64 !== "string" || avatar.jpegBase64.length > 266668 || !/^[A-Za-z0-9+/]+={0,2}$/.test(avatar.jpegBase64)) invalid();
    try {
      const bytes = Uint8Array.from(atob(avatar.jpegBase64), c => c.charCodeAt(0));
      if (bytes.length > 200000) invalid();
      const decoded = jpeg.decode(bytes, { useTArray: true, tolerantDecoding: false, maxResolutionInMP: 0.27, maxMemoryUsageInMB: 16 });
      if (decoded.width > 512 || decoded.height > 512 || decoded.width < 1 || decoded.height < 1) invalid();
      // Encode pixels only, stripping EXIF/location metadata and non-image payloads.
      image = jpeg.encode({ width: decoded.width, height: decoded.height, data: decoded.data }, 80).data;
      if (image.length > 200000) invalid();
    } catch { invalid(); }
  }
  return { username, handle, bio, revision: value.revision as number, action: avatar.action as string, image };
}

export async function readProfileBody(req: Request) {
  if (!req.headers.get("content-type")?.startsWith("application/json")) throw Error("invalid_profile");
  const reader = req.body?.getReader(); if (!reader) throw Error("invalid_profile");
  let size = 0, text = "";
  const decoder = new TextDecoder("utf-8", { fatal: true });
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.length; if (size > 280000) throw Error("invalid_profile");
      text += decoder.decode(value, { stream: true });
    }
    return JSON.parse(text + decoder.decode());
  } catch { throw Error("invalid_profile"); } finally { await reader.cancel(); }
}
