# Drafta plugin for Claude Code

Gives Claude access to your local [Drafta](https://github.com/rpegorov/drafta-mcp)
note library: search, read, create, append, tag and file notes. The server is the
`drafta-mcp` helper that ships inside Drafta.app, talks to Claude over stdio and
makes no network requests.

## Requirements

- macOS with Drafta.app installed in `/Applications`.

## Install

```
/plugin marketplace add rpegorov/drafta-mcp
/plugin install drafta@drafta
```

## Drafta.app in ~/Applications

The plugin launches `/Applications/Drafta.app/Contents/Helpers/drafta-mcp`. If the
app lives in `~/Applications`, add the server yourself instead:

```
claude mcp add drafta -- "$HOME/Applications/Drafta.app/Contents/Helpers/drafta-mcp"
```

## Read-only access

The server accepts `--read-only`, which publishes the read tools only. To use it,
register the server by hand with the flag instead of installing the plugin:

```
claude mcp add drafta -- /Applications/Drafta.app/Contents/Helpers/drafta-mcp --read-only
```

See the [repository README](https://github.com/rpegorov/drafta-mcp) for all flags,
the tool list and the privacy notes. The `formatting_guide` tool tells Claude which
Markdown Drafta renders.
