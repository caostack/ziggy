//! File system adapter - abstract interface for file I/O operations
const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const FileError = types.FileError;

/// FileSystem VTable - adapter implementations must provide these functions
pub const FileSystemVTable = struct {
    /// Open file and load content
    open: *const fn (*anyopaque, Allocator, []const u8) FileError![]const u8,

    /// Save content to file
    save: *const fn (*anyopaque, []const u8, []const u8) FileError!void,

    /// Check if file exists
    exists: *const fn (*anyopaque, []const u8) bool,

    /// Clean up resources
    deinit: *const fn (*anyopaque) void,
};

/// FileSystem interface - wraps any filesystem adapter implementation
pub const FileSystem = struct {
    ptr: *anyopaque,
    vtable: *const FileSystemVTable,

    const Self = @This();

    /// Create FileSystem wrapper from any implementation
    pub fn init(ptr: anytype, vtable: *const FileSystemVTable) Self {
        return .{
            .ptr = @ptrCast(@alignCast(ptr)),
            .vtable = vtable,
        };
    }

    /// Clean up resources
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }

    /// Open file and load content
    pub fn open(self: Self, allocator: Allocator, path: []const u8) FileError![]const u8 {
        return self.vtable.open(self.ptr, allocator, path);
    }

    /// Save content to file
    pub fn save(self: Self, path: []const u8, content: []const u8) FileError!void {
        return self.vtable.save(self.ptr, path, content);
    }

    /// Check if file exists
    pub fn exists(self: Self, path: []const u8) bool {
        return self.vtable.exists(self.ptr, path);
    }
};

/// NativeFileSystem - real filesystem implementation
pub const NativeFileSystem = struct {
    const Self = @This();

    /// Initialize
    pub fn init() Self {
        return .{};
    }

    /// Open file and load into buffer (UTF-8 validated)
    pub fn open(self: *Self, allocator: Allocator, path: []const u8) FileError![]const u8 {
        _ = self;
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => FileError.NotFound,
                error.PermissionDenied => FileError.PermissionDenied,
                else => FileError.ReadFailed,
            };
        };
        defer file.close();

        const stat = file.stat() catch return FileError.ReadFailed;
        const size = @as(usize, @intCast(stat.size));

        if (size == 0) {
            // Empty file
            return try allocator.dupe(u8, "");
        }

        const content = try allocator.alloc(u8, size);
        errdefer allocator.free(content);

        const n = file.readAll(content) catch return FileError.ReadFailed;
        if (n != size) return FileError.ReadFailed;

        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(content)) {
            return FileError.InvalidUtf8;
        }

        return content;
    }

    /// Save buffer content to file
    pub fn save(self: *Self, path: []const u8, content: []const u8) FileError!void {
        _ = self;
        const file = std.fs.cwd().createFile(path, .{ .read = true }) catch |err| {
            return switch (err) {
                error.PermissionDenied => FileError.PermissionDenied,
                else => FileError.WriteFailed,
            };
        };
        defer file.close();

        file.writeAll(content) catch return FileError.WriteFailed;
    }

    /// Check if file exists
    pub fn exists(self: *Self, path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Clean up (no-op for native filesystem)
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // ========================================================================
    // VTable implementation
    // ========================================================================

    /// Static VTable for FileSystem interface (must be static to avoid dangling pointer)
    pub const vtable = FileSystemVTable{
        .open = vtableOpen,
        .save = vtableSave,
        .exists = vtableExists,
        .deinit = vtableDeinit,
    };

    /// Create FileSystem wrapper
    pub fn fileSystem(self: *Self) FileSystem {
        return FileSystem.init(self, @constCast(&vtable));
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

test "NativeFileSystem - open non-existent file" {
    var fs = NativeFileSystem.init();
    const result = fs.open(std.testing.allocator, "/nonexistent/file.txt");
    try std.testing.expectError(FileError.NotFound, result);
}

test "NativeFileSystem - save and load file" {
    var fs = NativeFileSystem.init();
    const test_content = "Hello, World!\nUTF-8 test: 你好世界\n";

    // Save to temp file
    const temp_path = "/tmp/zig_adapter_test.txt";
    try fs.save(temp_path, test_content);

    // Load it back
    const loaded = try fs.open(std.testing.allocator, temp_path);
    defer std.testing.allocator.free(loaded);

    try std.testing.expectEqualStrings(test_content, loaded);

    // Clean up
    std.fs.cwd().deleteFile(temp_path) catch {};
}

test "NativeFileSystem - exists check" {
    var fs = NativeFileSystem.init();
    const existing_path = "/tmp/zig_adapter_exists_test.txt";
    const non_existent_path = "/tmp/zig_adapter_nonexistent_test_12345.txt";

    // Create temp file
    try fs.save(existing_path, "test");
    defer std.fs.cwd().deleteFile(existing_path) catch {};

    // Test existing file
    try std.testing.expect(fs.exists(existing_path));

    // Test non-existent file
    try std.testing.expect(!fs.exists(non_existent_path));
}

test "NativeFileSystem - interface wrapper" {
    var native = NativeFileSystem.init();
    var fs = native.fileSystem();

    const temp_path = "/tmp/zig_adapter_interface_test.txt";
    try fs.save(temp_path, "test content");

    const content = try fs.open(std.testing.allocator, temp_path);
    defer std.testing.allocator.free(content);

    try std.testing.expectEqualStrings("test content", content);

    std.fs.cwd().deleteFile(temp_path) catch {};
}

test "NativeFileSystem - reject invalid utf8" {
    var fs = NativeFileSystem.init();
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };

    const temp_path = "/tmp/zig_adapter_invalid_test.txt";

    // Write invalid bytes directly
    const file = std.fs.cwd().createFile(temp_path, .{}) catch |err| {
        try std.testing.expectEqual(error.AccessDenied, err);
        return;
    };
    defer {
        file.close();
        std.fs.cwd().deleteFile(temp_path) catch {};
    }

    file.writeAll(&invalid_utf8) catch return;

    // Should fail to open due to invalid UTF-8
    const result = fs.open(std.testing.allocator, temp_path);
    try std.testing.expectError(FileError.InvalidUtf8, result);
}
