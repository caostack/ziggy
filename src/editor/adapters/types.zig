//! Adapter types - shared error and type definitions
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Terminal-related errors
pub const TerminalError = error{
    NotATTY,
    IoctlFailed,
    WriteFailed,
    GetConsoleModeFailed,
    SetConsoleModeFailed,
};

/// Input-related errors
pub const InputError = error{
    ReadFailed,
    InvalidSequence,
};

/// File I/O related errors
pub const FileError = error{
    NotFound,
    PermissionDenied,
    InvalidUtf8,
    ReadFailed,
    WriteFailed,
    OutOfMemory,
};

/// Window size structure
pub const WindowSize = struct {
    rows: usize,
    cols: usize,
};

/// Key type - unified representation of keyboard input
pub const Key = union(enum) {
    // Control keys
    ctrl_c, // Exit
    ctrl_s, // Save
    ctrl_q, // Quit (with prompt)
    ctrl_f, // Find (future)

    // Navigation
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    home,
    end,
    page_up,
    page_down,

    // Editing
    escape,
    enter,
    backspace,
    delete,
    tab,

    // UTF-8 character (1-4 bytes stored inline)
    character: [4]u8,

    // Unknown/unsupported
    unknown,

    /// Check if key is a character
    pub fn isCharacter(self: Key) bool {
        return switch (self) {
            .character => true,
            else => false,
        };
    }

    /// Get character slice (only valid if isCharacter() is true)
    pub fn getCharacter(self: Key) ?[]const u8 {
        return switch (self) {
            .character => |bytes| blk: {
                // Find the actual length
                var len: usize = 4;
                for (bytes, 0..) |b, i| {
                    if (b == 0) {
                        len = i;
                        break;
                    }
                }
                break :blk bytes[0..len];
            },
            else => null,
        };
    }
};
