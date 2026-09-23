import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const build = mkdtempSync(join(tmpdir(), "bsmart-waitlist-test-"));
try {
  const compiled = spawnSync(process.execPath, [join(root, "node_modules/typescript/bin/tsc"), "server/waitlist/handler.ts", "--outDir", build, "--module", "commonjs", "--target", "ES2022", "--skipLibCheck", "--strict"], { cwd: root, stdio: "inherit" });
  if (compiled.status !== 0) process.exitCode = compiled.status || 1;
  else {
    const tests = spawnSync(process.execPath, ["--test", "server/waitlist/waitlist.test.cjs"], { cwd: root, stdio: "inherit", env: { ...process.env, BSMART_WAITLIST_TEST_BUILD: build } });
    process.exitCode = tests.status || 0;
  }
} finally { rmSync(build, { recursive: true, force: true }); }
