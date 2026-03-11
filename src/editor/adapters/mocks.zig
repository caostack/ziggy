//! Mock adapters - testing implementations for adapter interfaces
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const types = @import("types.zig");
const TerminalError = types.TerminalError;
const InputError = types.InputError;
const FileError = types.FileError;
const WindowSize = types.WindowSize;
const Key = types.Key;
const terminal = @import("terminal.zig");
const TerminalVTable = terminal.TerminalVTable;
const Terminal = terminal.Terminal;
const input = @import("input.zig");
const InputVTable = input.InputVTable;
const Input = input.Input;
const filesystem = @import("filesystem.zig");
const FileSystemVTable = filesystem.FileSystemVTable;
const FileSystem = filesystem.FileSystem;

/// MockTerminal - captures all terminal output for testing
pub const MockTerminal = struct {
    allocator: Allocator,
    output_buffer: ArrayList(u8),
    cursor_row: usize,
    cursor_col: usize,
    cursor_visible: bool,
    screen_cleared: bool,
    window_size: WindowSize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .output_buffer = ArrayList(u8).init(allocator),
            .cursor_row = 1,
            .cursor_col = 1,
            .cursor_visible = true,
            .screen_cleared = false,
            .window_size = .{ .rows = 24, .cols = 80 },
        };
    }

    pub fn deinit(self: *Self) void {
        self.output_buffer.deinit();
    }

    pub fn clearScreen(self: *Self) TerminalError!void {
        self.screen_cleared = true;
        self.output_buffer.clearRetainingCapacity();
    }

    pub fn clearLine(self: *Self) TerminalError!void {
        // Append clear line marker
        try self.output_buffer.appendSlice("[CLEAR_LINE]");
    }

    pub fn moveCursor(self: *Self, row: usize, col: usize) TerminalError!void {
        self.cursor_row = row;
        self.cursor_col = col;
    }

    pub fn hideCursor(self: *Self) TerminalError!void {
        self.cursor_visible = false;
    }

    pub fn showCursor(self: *Self) TerminalError!void {
        self.cursor_visible = true;
    }

    pub fn getWindowSize(self: *Self) TerminalError!WindowSize {
        return self.window_size;
    }

    pub fn writeAll(self: *Self, s: []const u8) TerminalError!void {
        try self.output_buffer.appendSlice(s);
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) TerminalError!void {
        _ = self;
        _ = fmt;
        _ = args;
        // Simplified for testing
    }

    /// Get captured output
    pub fn getOutput(self: Self) []const u8 {
        return self.output_buffer.items;
    }

    /// Clear captured output
    pub fn clearOutput(self: *Self) void {
        self.output_buffer.clearRetainingCapacity();
    }

    /// Set window size for testing
    pub fn setWindowSize(self: *Self, rows: usize, cols: usize) void {
        self.window_size = .{ .rows = rows, .cols = cols };
    }

    // VTable implementation
    pub fn vtable() TerminalVTable {
        return .{
            .deinit = vtableDeinit,
            .clearScreen = vtableClearScreen,
            .clearLine = vtableClearLine,
            .moveCursor = vtableMoveCursor,
            .hideCursor = vtableHideCursor,
            .showCursor = vtableShowCursor,
            .getWindowSize = vtableGetWindowSize,
            .writeAll = vtableWriteAll,
            .print = vtablePrint,
        };
    }

    pub fn terminal(self: *Self) Terminal {
        return Terminal.init(self, @constCast(&vtable()));
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableClearScreen(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.clearScreen();
    }

    fn vtableClearLine(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.clearLine();
    }

    fn vtableMoveCursor(ptr: *anyopaque, row: usize, col: usize) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursor(row, col);
    }

    fn vtableHideCursor(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.hideCursor();
    }

    fn vtableShowCursor(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.showCursor();
    }

    fn vtableGetWindowSize(ptr: *anyopaque) TerminalError!WindowSize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getWindowSize();
    }

    fn vtableWriteAll(ptr: *anyopaque, s: []const u8) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.writeAll(s);
    }

    fn vtablePrint(ptr: *anyopaque, fmt: []const u8, args: anytype) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.print(fmt, args);
    }
};

/// MockInput - provides predetermined key sequence for testing
pub const MockInput = struct {
    keys: ArrayList(Key),
    read_index: usize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .keys = ArrayList(Key).init(allocator),
            .read_index = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.keys.deinit();
    }

    /// Add a key to the sequence
    pub fn addKey(self: *Self, key: Key) !void {
        try self.keys.append(key);
    }

    /// Add a character key
    pub fn addChar(self: *Self, char: []const u8) !void {
        var buf: [4]u8 = undefined;
        @memcpy(buf[0..char.len], char);
        if (char.len < 4) {
            @memset(buf[char.len..], 0);
        }
        try self.addKey(.{ .character = buf });
    }

    pub fn readKey(self: *Self) InputError!Key {
        if (self.read_index >= self.keys.items.len) {
            return .unknown;
        }
        const key = self.keys.items[self.read_index];
        self.read_index += 1;
        return key;
    }

    /// Reset to beginning of key sequence
    pub fn reset(self: *Self) void {
        self.read_index = 0;
    }

    /// Check if all keys have been consumed
    pub fn isEmpty(self: Self) bool {
        return self.read_index >= self.keys.items.len;
    }

    // VTable implementation
    pub fn vtable() InputVTable {
        return .{
            .readKey = vtableReadKey,
            .deinit = vtableDeinit,
        };
    }

    pub fn input(self: *Self) Input {
        return Input.init(self, @constCast(&vtable()));
    }

    fn vtableReadKey(ptr: *anyopaque) InputError!Key {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.readKey();
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

/// MockFileSystem - in-memory file system for testing
pub const MockFileSystem = struct {
    allocator: Allocator,
    files: std.StringHashMap([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
            self.allocator.free(@constCast(entry.value_ptr.*));
        }
        self.files.deinit();
    }

    /// Create a file in the mock filesystem
    pub fn createFile(self: *Self, path: []const u8, content: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        const owned_content = try self.allocator.dupe(u8, content);

        if (self.files.fetchPut(owned_path, owned_content)) |old| {
            self.allocator.free(@constCast(old.key));
            self.allocator.free(@constCast(old.value));
        }
    }

    pub fn open(self: *Self, allocator: Allocator, path: []const u8) FileError![]const u8 {
        const content = self.files.get(path) orelse return FileError.NotFound;
        return try allocator.dupe(u8, content);
    }

    pub fn save(self: *Self, path: []const u8, content: []const u8) FileError!void {
        self.createFile(path, content) catch return FileError.WriteFailed;
    }

    pub fn exists(self: *Self, path: []const u8) bool {
        return self.files.contains(path);
    }

    /// Delete a file from the mock filesystem
    pub fn deleteFile(self: *Self, path: []const u8) bool {
        if (self.files.fetchRemove(path)) |removed| {
            self.allocator.free(@constCast(removed.key));
            self.allocator.free(@constCast(removed.value));
            return true;
        }
        return false;
    }

    // VTable implementation
    pub fn vtable() FileSystemVTable {
        return .{
            .open = vtableOpen,
            .save = vtableSave,
            .exists = vtableExists,
            .deinit = vtableDeinit,
        };
    }

    pub fn fileSystem(self: *Self) FileSystem {
        return FileSystem.init(self, @constCast(&vtable()));
    }

    fn vtableOpen(ptr: *anyopaque, allocator: Allocator, path: []const u8) FileError![]const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.open(allocator, path);
    }

    fn vtableSave(ptr: *anyopaque, path: []const u8, content: []const u8) FileError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.save(path, content);
    }

    fn vtableExists(ptr: *anyopaque, path: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.exists(path);
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MockTerminal - capture output" {
    var mock = MockTerminal.init(std.testing.allocator);
    defer mock.deinit();

    try mock.writeAll("Hello");
    try mock.writeAll(" World");

    try std.testing.expectEqualStrings("Hello World", mock.getOutput());
}

test "MockTerminal - cursor operations" {
    var mock = MockTerminal.init(std.testing.allocator);
    defer mock.deinit();

    try mock.moveCursor(5, 10);
    try std.testing.expectEqual(@as(usize, 5), mock.cursor_row);
    try std.testing.expectEqual(@as(usize, 10), mock.cursor_col);

    try mock.hideCursor();
    try std.testing.expect(!mock.cursor_visible);

    try mock.showCursor();
    try std.testing.expect(mock.cursor_visible);
}

test "MockTerminal - interface wrapper" {
    var mock = MockTerminal.init(std.testing.allocator);
    defer mock.deinit();

    var term = mock.terminal();
    try term.writeAll("test");
    try std.testing.expectEqualStrings("test", mock.getOutput());
}

test "MockInput - key sequence" {
    var mock = MockInput.init(std.testing.allocator);
    defer mock.deinit();

    try mock.addKey(.arrow_up);
    try mock.addKey(.arrow_down);
    try mock.addChar("a");

    var inp = mock.input();

    try std.testing.expectEqual(Key.arrow_up, try inp.readKey());
    try std.testing.expectEqual(Key.arrow_down, try inp.readKey());

    const char_key = try inp.readKey();
    try std.testing.expect(char_key.isCharacter());
}

test "MockInput - reset" {
    var mock = MockInput.init(std.testing.allocator);
    defer mock.deinit();

    try mock.addKey(.ctrl_c);
    try mock.addKey(.ctrl_s);

    _ = try mock.readKey();
    try std.testing.expect(!mock.isEmpty());

    _ = try mock.readKey();
    try std.testing.expect(mock.isEmpty());

    mock.reset();
    try std.testing.expect(!mock.isEmpty());
}

test "MockFileSystem - create and read" {
    var mock = MockFileSystem.init(std.testing.allocator);
    defer mock.deinit();

    try mock.createFile("/test.txt", "Hello World");

    const content = try mock.open(std.testing.allocator, "/test.txt");
    defer std.testing.allocator.free(content);

    try std.testing.expectEqualStrings("Hello World", content);
}

test "MockFileSystem - exists check" {
    var mock = MockFileSystem.init(std.testing.allocator);
    defer mock.deinit();

    try std.testing.expect(!mock.exists("/test.txt"));

    try mock.createFile("/test.txt", "content");
    try std.testing.expect(mock.exists("/test.txt"));

    _ = mock.deleteFile("/test.txt");
    try std.testing.expect(!mock.exists("/test.txt"));
}

test "MockFileSystem - interface wrapper" {
    var mock = MockFileSystem.init(std.testing.allocator);
    defer mock.deinit();

    var fs = mock.fileSystem();

    try fs.save("/test.txt", "content");
    try std.testing.expect(fs.exists("/test.txt"));

    const content = try fs.open(std.testing.allocator, "/test.txt");
    defer std.testing.allocator.free(content);

    try std.testing.expectEqualStrings("content", content);
}
