// 生成 Apple "Sign in with Apple" 的 client secret（一段 ES256 JWT），
// 用于粘进 Supabase → Authentication → Providers → Apple → Secret Key (for OAuth)。
//
// Apple 规定该 secret 最长有效 6 个月，到期需重新生成（再跑一次本脚本）。
// 用法：node scripts/gen-apple-secret.mjs [可选的 .p8 路径]
//
// 注意：.p8 是私钥，已被 .gitignore 忽略；本脚本只读取它、不打印它。
import { readFileSync } from "node:fs";
import crypto from "node:crypto";

const TEAM_ID = "YPCJA6K48J";          // App ID Prefix / Team ID
const KEY_ID = "7Q328MY4BF";           // Keys 里那个 Key 的 ID
const SERVICES_ID = "xyz.redditalpha.web"; // Services ID = OAuth client_id（JWT 的 sub）
const P8_PATH = process.argv[2] || "/Users/windz7z/Desktop/crypto_us/AuthKey_7Q328MY4BF.p8";

const b64url = (buf) => Buffer.from(buf).toString("base64url");

const now = Math.floor(Date.now() / 1000);
const exp = now + 86400 * 180; // 180 天（Apple 上限约 182 天）

const header = { alg: "ES256", kid: KEY_ID };
const payload = { iss: TEAM_ID, iat: now, exp, aud: "https://appleid.apple.com", sub: SERVICES_ID };

const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
const privateKey = crypto.createPrivateKey(readFileSync(P8_PATH, "utf8"));
const signature = crypto.sign("sha256", Buffer.from(signingInput), { key: privateKey, dsaEncoding: "ieee-p1363" });
const jwt = `${signingInput}.${b64url(signature)}`;

// JWT 打到 stdout（方便复制），元信息打到 stderr
console.log(jwt);
console.error(`\n[Services ID] ${SERVICES_ID}`);
console.error(`[过期时间]   ${new Date(exp * 1000).toISOString()}  ← 到期前务必重新生成`);
