//! Ziggy - UTF-8 Terminal Text Editor Library
//!
//! A nano-like text editor with full UTF-8 support, written in Zig.
//! Named after its friendly helper spirit that makes editing text a joy.
//!
//! Features:
//! - UTF-8 text editing with gap buffer
//! - Raw terminal mode with ANSI escape sequences
//! - Arrow key navigation
//! - File open/save operations
//! - Status bar display
const std = @import("std");

// Re-export editor types for library consumers
pub const Editor = @import("editor/editor.zig").Editor;
pub const Buffer = @import("editor/buffer.zig").Buffer;
pub const Terminal = @import("editor/terminal.zig").Terminal;
pub const Screen = @import("editor/screen.zig").Screen;
pub const Key = @import("editor/input.zig").Key;
pub const FileIO = @import("editor/file_io.zig").FileIO;

// Legacy function for compatibility
pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("UTF-8 Terminal Text Editor\n", .{});
    try stdout.flush();
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

// Legacy add function for compatibility
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
