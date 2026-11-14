# cmux image preview

A Claude Code `PostToolUse` hook. When Claude creates or opens an image (a screenshot, a generated image, a Playwright capture, an MCP tool's image), it shows up in a **"Claude images"** split next to the Claude pane in [cmux](https://cmux.dev).

Claude Code redraws its own screen, which wipes out any image drawn into it, so the images go to a separate split. The split draws them with the kitty graphics protocol, which cmux supports because it is built on Ghostty.

## What it picks up

- `Read` / `Write` of an image file
- image paths in a Bash or MCP call (or its output) when the file changed in the last 3 minutes
- base64 images returned inline by MCP tools (saved to `captures/` first)

Outside cmux it does nothing.

## Install

```sh
mkdir -p ~/.claude/hooks/cmux-image-viewer
cp hook.py viewer.py ~/.claude/hooks/cmux-image-viewer/
```

Add this to `~/.claude/settings.json`, merging it into any hooks you already have:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Read|Write|Bash|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/cmux-image-viewer/hook.py",
            "async": true,
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

Requires macOS (it uses `sips` to read image sizes and convert formats), `python3`, and cmux.

## Notes

- Each Claude pane gets its own viewer split. If you close it, it reopens on the next image.
- Images are scaled to fit the pane, and you can scroll back through earlier ones.
- If something doesn't show up, errors are logged to `state/errors.log`.
