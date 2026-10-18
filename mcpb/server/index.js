#!/usr/bin/env node
"use strict";
const { spawn } = require("node:child_process");
const { accessSync, constants } = require("node:fs");
const os = require("node:os");

const DEFAULT_HELPER = "/Applications/Drafta.app/Contents/Helpers/drafta-mcp";
const HOMEPAGE = "https://github.com/rpegorov/drafta-mcp";
const SIGNAL_EXIT_BASE = 128;
// DRAFTA_MCP_HELPER exists so tests can substitute a fake helper.
const helper = process.env.DRAFTA_MCP_HELPER || DEFAULT_HELPER;

try {
  accessSync(helper, constants.X_OK);
} catch {
  process.stderr.write(`Drafta is not installed: ${helper} not found. Install Drafta from ${HOMEPAGE}\n`);
  process.exit(1);
}

const child = spawn(helper, process.argv.slice(2), { stdio: "inherit" });

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => child.kill(signal));
}

child.on("error", (err) => {
  process.stderr.write(`Failed to start ${helper}: ${err.message}\n`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.exit(SIGNAL_EXIT_BASE + os.constants.signals[signal]);
  }
  process.exit(code ?? 1);
});
