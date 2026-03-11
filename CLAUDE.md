# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Required Reading

**IMPORTANT**: Before starting any work in this repository, you must read the Zig mastery memory file:
```
~/.claude/learning/zig/mastery/MEMORY.md
```

This file contains important patterns, conventions, and best practices for Zig development that should be applied to all work in this repository.

## Project Overview

This is a Zig project following the library + executable pattern defined by Zig's standard project template. It uses Zig 0.15.2+.

## Architecture

The project is structured with two distinct modules:

1. **Library module** (`src/root.zig`): Core business logic and reusable functions. Public declarations here are exposed to consumers of this package via the `work` module name.

2. **Executable module** (`src/main.zig`): CLI entry point that imports and uses the library module via `@import("work")`.

The build system is defined in `build.zig` with the following build graph:
- `work` module for library functionality (root: `src/root.zig`)
- `work` executable for CLI (root: `src/main.zig`, imports the `work` module)
- Separate test executables for each module (tests run in parallel)

## Common Commands

```bash
# Build the project (outputs to zig-out/)
zig build

# Run the application
zig build run

# Run all tests (both library and executable tests in parallel)
zig build test

# Run with fuzzing enabled
zig build test -- --fuzz

# Build with specific optimization mode
zig build --release fast   # or safe, small
```

## Development Notes

- Tests use Zig's built-in `test` blocks and `std.testing`
- Fuzzing tests can be added using `std.testing.fuzz`
- The project uses `build.zig.zon` for Zig package metadata
- No external dependencies are currently declared

## Adding Dependencies

Use `zig fetch --save <url>` to add new dependencies to `build.zig.zon`, then modify `build.zig` to include them in the appropriate modules.
