# Relapse MCP

Use Relapse from your MCP client to inspect Roblox sessions, search scripts, and run Luau.

## Setup

Install Node.js 22 or newer with npm, then start Relapse and join a Roblox game.

Add the following server to your MCP client's configuration, then restart the client.

### JSON configuration

```json
{
  "mcpServers": {
    "relapse": {
      "command": "npx",
      "args": ["-y", "relapse-mcp@latest"]
    }
  }
}
```

### Codex

Add this to `~/.codex/config.toml`:

```toml
[mcp_servers.relapse]
command = "npx"
args = ["-y", "relapse-mcp@latest"]
startup_timeout_sec = 60
```

## Usage

Ask your assistant to list connected clients, inspect the current game, find instances, read scripts, check console output, or run Luau.

### Multiple profiles

Running Relapse profiles are discovered automatically. Use `list-clients` to find their IDs, then `set-active-client` to choose the default for your MCP session. To target a profile for a single tool call, pass its `clientId`.

Start profiles in Relapse before using them through MCP.

### Connection options

Set these environment variables in your MCP server configuration if needed:

| Variable | Usage |
| --- | --- |
| `RELAPSE_SOCKET_PATH` | Connect to one socket, such as `/tmp/relapse-Default.sock`. |
| `RELAPSE_SOCKET_DIR` | Look for running profiles in a directory other than `/tmp`. Ignored when `RELAPSE_SOCKET_PATH` is set. |
