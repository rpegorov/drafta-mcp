#!/usr/bin/env bash
# Packs mcpb/ into dist/drafta-mcp.mcpb and records its SHA-256 in server.json.
set -euo pipefail

MCPB_VERSION="2.1.2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/dist/drafta-mcp.mcpb"

mkdir -p "$ROOT/dist"
npx -y "@anthropic-ai/mcpb@$MCPB_VERSION" validate "$ROOT/mcpb/manifest.json"
npx -y "@anthropic-ai/mcpb@$MCPB_VERSION" pack "$ROOT/mcpb" "$BUNDLE"

SHA256="$(shasum -a 256 "$BUNDLE" | cut -d' ' -f1)"
SHA256="$SHA256" node -e '
const fs = require("node:fs");
const path = process.argv[1];
const server = JSON.parse(fs.readFileSync(path, "utf8"));
server.packages[0].fileSha256 = process.env.SHA256;
fs.writeFileSync(path, JSON.stringify(server, null, 2) + "\n");
' "$ROOT/server.json"

echo "$BUNDLE sha256=$SHA256"
