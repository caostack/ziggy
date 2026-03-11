//! Adapters module - abstract interfaces for external systems
//! Provides VTable-based interfaces for terminal, input, and filesystem
pub const types = @import("types.zig");
pub const terminal = @import("terminal.zig");
pub const input = @import("input.zig");
pub const filesystem = @import("filesystem.zig");
pub const mocks = @import("mocks.zig");

// Re-export types
pub const TerminalError = types.TerminalError;
pub const InputError = types.InputError;
pub const FileError = types.FileError;
pub const WindowSize = types.WindowSize;
pub const Key = types.Key;

// Re-export terminal types
pub const TerminalVTable = terminal.TerminalVTable;
pub const Terminal = terminal.Terminal;
pub const NativeTerminal = terminal.NativeTerminal;

// Re-export input types
pub const InputVTable = input.InputVTable;
pub const Input = input.Input;
pub const NativeInput = input.NativeInput;

// Re-export filesystem types
pub const FileSystemVTable = filesystem.FileSystemVTable;
pub const FileSystem = filesystem.FileSystem;
pub const NativeFileSystem = filesystem.NativeFileSystem;

// Re-export mock types
pub const MockTerminal = mocks.MockTerminal;
pub const MockInput = mocks.MockInput;
pub const MockFileSystem = mocks.MockFileSystem;

test {
    _ = @import("types.zig");
    _ = @import("terminal.zig");
    _ = @import("input.zig");
    _ = @import("filesystem.zig");
    _ = @import("mocks.zig");
}
