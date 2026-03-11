const std = @import("std");
const ziggy = @import("ziggy");

// New architecture imports
const FullEditor = ziggy.integration.FullEditor;
const NativeTerminal = ziggy.NativeTerminal;
const NativeInput = ziggy.NativeInput;
const NativeFileSystem = ziggy.NativeFileSystem;

pub fn main() !void {
    // Use smp_allocator (performant, thread-safe)
    const allocator = std.heap.smp_allocator;

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const filename = if (args.len > 1) args[1] else null;

    // Enable raw mode
    var native_terminal = NativeTerminal.enableRawMode() catch |err| {
        std.debug.print("Error: Cannot enable raw mode - {}\n", .{err});
        std.debug.print("Make sure you're running in a terminal.\n", .{});
        return;
    };
    errdefer native_terminal.disableRawMode();

    // Initialize adapters
    var native_input = NativeInput.init();
    var native_fs = NativeFileSystem.init();

    // Get terminal and input interfaces
    const terminal = native_terminal.terminal();
    const input = native_input.input();
    const filesystem = native_fs.fileSystem();

    // Initialize editor with or without file
    if (filename) |path| {
        var editor = FullEditor.initFile(
            allocator,
            terminal,
            input,
            filesystem,
            path,
        ) catch |err| {
            std.debug.print("Error opening file '{s}': {}\n", .{ path, err });
            return;
        };
        defer editor.deinit();

        // Run event loop
        editor.run() catch |err| {
            std.debug.print("Editor error: {}\n", .{err});
        };
    } else {
        var editor = FullEditor.init(
            allocator,
            terminal,
            input,
            filesystem,
        ) catch |err| {
            std.debug.print("Error initializing editor: {}\n", .{err});
            return;
        };
        defer editor.deinit();

        // Run event loop
        editor.run() catch |err| {
            std.debug.print("Editor error: {}\n", .{err});
        };
    }
}

test "simple test" {
    try std.testing.expect(true);
}
