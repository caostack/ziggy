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

// Legacy editor types (keep for backward compatibility)
pub const Editor = @import("editor/editor.zig").Editor;
pub const Buffer = @import("editor/buffer.zig").Buffer;
pub const Terminal = @import("editor/terminal.zig").Terminal;
pub const Screen = @import("editor/screen.zig").Screen;
pub const FileIO = @import("editor/file_io.zig").FileIO;

// New layered architecture - Core module
pub const core = @import("editor/core/mod.zig");

// Re-export core types
pub const Position = core.Position;
pub const Range = core.Range;
pub const EditorError = core.EditorError;
pub const Document = core.Document;
pub const DocumentVTable = core.DocumentVTable;
pub const Selection = core.Selection;
pub const SelectionManager = core.SelectionManager;
pub const Operation = core.Operation;
pub const Transaction = core.Transaction;
pub const UndoStack = core.UndoStack;
pub const Viewport = core.Viewport;

// New layered architecture - Storage module
pub const storage = @import("editor/storage/mod.zig");

// Re-export storage types
pub const GapBuffer = storage.GapBuffer;
pub const PieceTable = storage.PieceTable;
pub const MockDocument = storage.MockDocument;

// New layered architecture - Integration module
pub const integration = @import("editor/integration.zig");

// Re-export integration types
pub const EditorState = integration.EditorState;

// New layered architecture - Adapters module
pub const adapters = @import("editor/adapters/mod.zig");

// Re-export adapter types
pub const TerminalError = adapters.TerminalError;
pub const InputError = adapters.InputError;
pub const FileError = adapters.FileError;
pub const Key = adapters.Key;
pub const WindowSize = adapters.WindowSize;
pub const NativeTerminal = adapters.NativeTerminal;
pub const NativeInput = adapters.NativeInput;
pub const NativeFileSystem = adapters.NativeFileSystem;
pub const MockTerminal = adapters.MockTerminal;
pub const MockInput = adapters.MockInput;
pub const MockFileSystem = adapters.MockFileSystem;

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
