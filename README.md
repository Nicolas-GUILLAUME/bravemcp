# BraveMCP

An MCP (Model Context Protocol) server that provides browser automation capabilities for the Brave browser. Enables AI models like Claude to control and interact with web browsers through a standardized interface.

## Prerequisites

- Ruby 3.x
- Bundler
- Brave Browser (macOS, or Windows via WSL2 — see below)
- ImageMagick (for screenshot resizing)

## Installation

Install ImageMagick if needed (Ubuntu/WSL2):

```bash
sudo apt-get install -y imagemagick
```

```bash
git clone <repository-url>
cd BraveMCP
bundle install
chmod +x bin/brave_mcp
```

## Usage

### 1. Run the MCP server

The server automatically launches Brave with a dedicated profile. No manual browser launch needed.

```bash
bin/brave_mcp
```

On first run, sign into your accounts in the Brave window that opens. Your sessions persist across restarts since the profile is saved to disk.

If Brave is already running with `--remote-debugging-port=9222`, the server connects to it instead of launching a new instance.

#### macOS

The profile is stored at `~/.brave-mcp-profile`. Brave is expected at its default installation path.

#### Windows (WSL2)

WSL2 is supported out of the box. The server detects WSL2 automatically and:

- Launches the Windows Brave executable (`C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe`)
- Stores the profile at `C:\Users\<you>\.brave-mcp-profile` (a native Windows path, avoiding UNC path issues)

**Required one-time setup:** enable mirrored networking so WSL2 can reach the Windows debug port. Create `C:\Users\<you>\.wslconfig` with:

```ini
[wsl2]
networkingMode=mirrored
```

Finally, restart WSL by running `wsl --shutdown` from a Windows terminal.

### 2. Configure Claude Code

Add to your Claude Code MCP settings (global settings under `~/.claude/mcp.json`):

```json
{
  "mcpServers": {
    "brave": {
      "command": "/path/to/bravemcp/bin/brave_mcp"
    }
  }
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BRAVE_MCP_PROFILE` | `~/.brave-mcp-profile` (macOS) / `C:\Users\<you>\.brave-mcp-profile` (WSL2) | Path to the browser profile directory |
| `BRAVE_MCP_PATH` | `/Applications/Brave Browser.app/Contents/MacOS/Brave Browser` (macOS) / `/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe` (WSL2) | Path to the Brave executable |

## Available Tools

| Category | Tools |
|----------|-------|
| **Navigation** | `navigate`, `reload`, `back`, `forward`, `get_url` |
| **Automation** | `click`, `type`, `fill`, `select`, `hover`, `scroll`, `focus` |
| **Content** | `get_html`, `get_text`, `get_title`, `screenshot` |
| **Inspection** | `get_element_info`, `query_selector_all` |
| **JavaScript** | `evaluate`, `wait_for_selector`, `wait_for_navigation` |
| **Console** | `get_console_logs`, `clear_console` |
| **Network** | `get_network_requests`, `get_request_details`, `clear_network` |
| **Performance** | `get_performance_metrics` |
| **Cookies** | `get_cookies`, `set_cookie`, `delete_cookies` |
| **Storage** | `get_local_storage`, `set_local_storage` |

## Dependencies

- [fast-mcp](https://github.com/contextco/fast-mcp) - MCP server framework
- [ferrum](https://github.com/rubycdp/ferrum) - Chrome DevTools Protocol driver

## License

MIT
