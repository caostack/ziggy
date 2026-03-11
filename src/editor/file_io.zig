//! File I/O operations with UTF-8 validation
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FileIOError = error{
    NotFound,
    PermissionDenied,
    InvalidUtf8,
    ReadFailed,
    WriteFailed,
};

pub const FileIO = struct {
    /// Open file and load into buffer (UTF-8 validated)
    pub fn open(allocator: Allocator, path: []const u8) ![]const u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => FileIOError.NotFound,
                error.PermissionDenied => FileIOError.PermissionDenied,
                else => FileIOError.ReadFailed,
            };
        };
        defer file.close();

        const stat = file.stat() catch return FileIOError.ReadFailed;
        const size = @as(usize, @intCast(stat.size));

        if (size == 0) {
            // Empty file
            return try allocator.dupe(u8, "");
        }

        const content = try allocator.alloc(u8, size);
        errdefer allocator.free(content);

        const n = file.readAll(content) catch return FileIOError.ReadFailed;
        if (n != size) return FileIOError.ReadFailed;

        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(content)) {
            return FileIOError.InvalidUtf8;
        }

        return content;
    }

    /// Save buffer content to file
    pub fn save(path: []const u8, content: []const u8) !void {
        const file = std.fs.cwd().createFile(path, .{ .read = true }) catch |err| {
            return switch (err) {
                error.PermissionDenied => FileIOError.PermissionDenied,
                else => FileIOError.WriteFailed,
            };
        };
        defer file.close();

        file.writeAll(content) catch return FileIOError.WriteFailed;
    }

    /// Check if file exists
    pub fn exists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }
};

test "open non-existent file" {
    const result = FileIO.open(std.testing.allocator, "/nonexistent/file.txt");
    try std.testing.expectError(FileIOError.NotFound, result);
}

test "save and load file" {
    const test_content = "Hello, World!\nUTF-8 test: 你好世界\n";

    // Save to temp file
    const temp_path = "/tmp/zig_editor_test.txt";
    try FileIO.save(temp_path, test_content);

    // Load it back
    const loaded = try FileIO.open(std.testing.allocator, temp_path);
    defer std.testing.allocator.free(loaded);

    try std.testing.expectEqualStrings(test_content, loaded);

    // Clean up
    std.fs.cwd().deleteFile(temp_path) catch {};
}

test "validate utf8 content" {
    const valid_utf8 = "Hello 世界 🚀";

    // Should succeed
    const temp_path = "/tmp/zig_editor_utf8_test.txt";
    try FileIO.save(temp_path, valid_utf8);

    const loaded = try FileIO.open(std.testing.allocator, temp_path);
    defer std.testing.allocator.free(loaded);

    try std.testing.expectEqualStrings(valid_utf8, loaded);

    // Clean up
    std.fs.cwd().deleteFile(temp_path) catch {};
}

test "reject invalid utf8" {
    // Invalid UTF-8 sequence
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };

    const temp_path = "/tmp/zig_editor_invalid_test.txt";

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
    const result = FileIO.open(std.testing.allocator, temp_path);
    try std.testing.expectError(FileIOError.InvalidUtf8, result);
}

test "file exists check" {
    const existing_path = "/tmp/zig_editor_exists_test.txt";
    const non_existent_path = "/tmp/zig_editor_nonexistent_test_12345.txt";

    // Create temp file
    try FileIO.save(existing_path, "test");
    defer std.fs.cwd().deleteFile(existing_path) catch {};

    // Test existing file
    try std.testing.expect(FileIO.exists(existing_path));

    // Test non-existent file
    try std.testing.expect(!FileIO.exists(non_existent_path));
}
