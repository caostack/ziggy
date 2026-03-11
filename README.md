# Ziggy

A toy terminal text editor written in Zig, following Zig's design philosophy.

## Zig Philosophy

This project strictly follows Zig's design principles:
- ✅ **Explicit** - No hidden allocations or magic
- ✅ **Manual Resource Management** - All resources managed with `defer`
- ✅ **Performance Transparent** - Zero-copy, slice-based
- ✅ **Comptime** - Leverage compile-time computation
- ✅ **Simple** - No OOP abstractions, just structs and functions

See [ZIG_PHILOSOPHY.md](ZIG_PHILOSOPHY.md) for details.

## Features

- ✨ UTF-8 support
- ⌨️ Basic terminal editing
- 📝 File read/write
- 🎯 Gap Buffer data structure

## Keybindings

- `Ctrl+S` - Save
- `Ctrl+Q` - Quit
- `Ctrl+C` - Force quit
- Arrow keys - Move cursor
- Enter - New line
- Backspace - Delete

## Building & Running

```bash
# Build
zig build

# Run
zig build run

# Edit a file
zig build run -- your-file.txt
```

## Quality & Philosophy

We follow Zig's design principles, see [TEAM_CONVENTIONS.md](TEAM_CONVENTIONS.md) for our team agreements.

### Quality Gate
```bash
./quality-gate.sh
```

Note: Automated checks can only catch surface-level issues. Real quality comes from:
- ✅ Human code review in PRs
- ✅ Team discussions and consensus
- ✅ Learning from Zig standard library

See [ZIG_PHILOSOPHY.md](ZIG_PHILOSOPHY.md) for philosophy details.

## Quality Gate

```bash
./quality-gate.sh
```

The quality gate runs automatically on git commits and in CI/CD.

## Note

⚠️ **This is a toy project** for learning and demonstrating Zig programming. Not intended for production use.

## Requirements

- Zig 0.15.2 or later

## License

MIT License
