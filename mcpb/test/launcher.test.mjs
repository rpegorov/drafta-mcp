import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, chmodSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const launcher = join(dirname(fileURLToPath(import.meta.url)), "..", "server", "index.js");

function runLauncher(helper, args = []) {
  return spawnSync(process.execPath, [launcher, ...args], {
    env: { ...process.env, DRAFTA_MCP_HELPER: helper },
    encoding: "utf8",
  });
}

test("missing helper exits non-zero with an install hint", () => {
  const result = runLauncher("/nonexistent/drafta-mcp");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /^Drafta is not installed: \/nonexistent\/drafta-mcp not found\. Install Drafta from https:\/\/github\.com\/rpegorov\/drafta-mcp\n$/);
});

test("arguments and exit code reach the helper and come back", () => {
  const dir = mkdtempSync(join(tmpdir(), "launcher-"));
  try {
    const helper = join(dir, "fake-helper");
    writeFileSync(helper, '#!/bin/sh\necho "$@"\nexit 7\n');
    chmodSync(helper, 0o755);
    const result = runLauncher(helper, ["--read-only", "--library", "/x"]);
    assert.equal(result.status, 7);
    assert.equal(result.stdout, "--read-only --library /x\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
