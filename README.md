# claude-code-statusline

A small status line for [Claude Code](https://claude.com/claude-code) that shows:

```
Opus 4.7 · ⎇ main · ████░░░░░░ 38% · $1.24
```

- model name
- current git branch
- context window usage as a 10-block bar + percentage (green / yellow / red)
- session cost in USD

The context % is derived from the latest `assistant.message.usage` entry in the active transcript (`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`), divided by `200k` for standard models or `1M` for `[1m]`/`-1m` variants.

## What's different from a naive implementation

Two cases where most transcript-scanning status lines drop to **0%**:

1. **Right after `/compact`.** The transcript ends with an `isCompactSummary: true` marker before the next assistant turn lands. This script remembers the last usage value seen *before* the marker and falls back to it during that gap, so the bar stays sensible until the first post-compact reply updates it.
2. **Right after `/resume`.** When `/resume` keeps writing to the same transcript file, this script still reads the prior usage entries correctly. (For the rarer case where `/resume` opens a brand-new transcript file with no usage entries yet, the script briefly shows 0% — there's no reliable parent-session pointer to follow, so it doesn't guess.)

## Requirements

- bash
- `jq`
- Claude Code

On macOS: `brew install jq`.

## Install

```bash
git clone https://github.com/<you>/claude-code-statusline.git
cd claude-code-statusline
./install.sh                              # installs into ~/.claude
./install.sh ~/.claude-work               # or any other Claude config dir
CLAUDE_CONFIG_DIR=~/.claude-personal ./install.sh
```

The installer copies `statusline.sh` to `<target>/hooks/statusline.sh` and patches `<target>/settings.json` to add:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"<target>/hooks/statusline.sh\""
  }
}
```

It preserves the rest of `settings.json` via `jq`.

## Manual install

If you'd rather wire it up by hand, copy `statusline.sh` anywhere on disk, make it executable, and add this to your `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/absolute/path/to/statusline.sh\""
  }
}
```

## License

MIT — see [LICENSE](LICENSE).
