//! MockDocument - Simple in-memory document storage for testing
//! Fully implements DocumentVTable with editable content
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const document = @import("../core/document.zig");
const DocumentVTable = document.DocumentVTable;
const Document = document.Document;
const DocumentError = document.DocumentError;

/// MockDocument - Simple arraylist-based document for testing
pub const MockDocument = struct {
    allocator: Allocator,
    content: ArrayList(u8),
    line_starts: ArrayList(usize),
    cursor_row: usize,
    cursor_col: usize,
    modified: bool,

    const Self = @This();

    /// Initialize empty MockDocument
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .content = ArrayList(u8).init(allocator),
            .line_starts = ArrayList(usize).init(allocator),
            .cursor_row = 0,
            .cursor_col = 0,
            .modified = false,
        };
    }

    /// Initialize with content
    pub fn initContent(allocator: Allocator, content: []const u8) !Self {
        if (!std.unicode.utf8ValidateSlice(content)) {
            return DocumentError.InvalidUtf8;
        }

        var self = Self.init(allocator);
        errdefer self.deinit();

        try self.content.appendSlice(content);
        try self.buildLineIndex();

        return self;
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.content.deinit();
        self.line_starts.deinit();
    }

    /// Build line index from content
    fn buildLineIndex(self: *Self) !void {
        self.line_starts.clearRetainingCapacity();
        try self.line_starts.append(0);

        for (self.content.items, 0..) |c, i| {
            if (c == '\n') {
                try self.line_starts.append(i + 1);
            }
        }
    }

    /// Get line count
    pub fn getLineCount(self: *const Self) usize {
        return self.line_starts.items.len;
    }

    /// Get line content by index
    pub fn getLine(self: *const Self, line_num: usize) ?[]const u8 {
        if (line_num >= self.line_starts.items.len) return null;

        const start = self.line_starts.items[line_num];
        const end = if (line_num + 1 < self.line_starts.items.len)
            self.line_starts.items[line_num + 1] - 1 // exclude newline
        else
            self.content.items.len;

        if (start >= end) return "";
        return self.content.items[start..end];
    }

    /// Get line length
    pub fn getLineLength(self: *const Self, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        return line.len;
    }

    /// Insert text at byte offset
    pub fn insertAt(self: *Self, pos: usize, text: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(text)) {
            return DocumentError.InvalidUtf8;
        }
        if (pos > self.content.items.len) {
            return DocumentError.InvalidPosition;
        }

        try self.content.insertSlice(pos, text);
        self.modified = true;

        // Rebuild line index if newline inserted
        for (text) |c| {
            if (c == '\n') {
                try self.buildLineIndex();
                break;
            }
        }
    }

    /// Delete text range
    pub fn deleteRange(self: *Self, start: usize, end: usize) !void {
        if (start > end or end > self.content.items.len) {
            return DocumentError.InvalidPosition;
        }

        // Remove elements one by one (simple but inefficient)
        // This is a mock for testing, not production code
        var i: usize = start;
        while (i < end) : (i += 1) {
            _ = self.content.orderedRemove(start);
        }

        self.modified = true;
        try self.buildLineIndex();
    }

    /// Get character at position
    pub fn getCharAt(self: *const Self, pos: usize) ?u8 {
        if (pos >= self.content.items.len) return null;
        return self.content.items[pos];
    }

    /// Get total length
    pub fn getTotalLength(self: *const Self) usize {
        return self.content.items.len;
    }

    /// Check if modified
    pub fn isModified(self: *const Self) bool {
        return self.modified;
    }

    /// Clear modified flag
    pub fn clearModified(self: *Self) void {
        self.modified = false;
    }

    /// Export as slice
    pub fn toSlice(self: *const Self, allocator: Allocator) ![]const u8 {
        return try allocator.dupe(u8, self.content.items);
    }

    /// Get cursor row
    pub fn getCursorRow(self: *const Self) usize {
        return self.cursor_row;
    }

    /// Get cursor column
    pub fn getCursorCol(self: *const Self) usize {
        return self.cursor_col;
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, row: usize, col: usize) void {
        self.cursor_row = @min(row, self.line_starts.items.len -| 1);
        const line_len = self.getLineLength(self.cursor_row);
        self.cursor_col = @min(col, line_len);
    }

    /// Move cursor up
    pub fn moveCursorUp(self: *Self) bool {
        if (self.cursor_row == 0) return false;
        self.cursor_row -= 1;
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }
        return true;
    }

    /// Move cursor down
    pub fn moveCursorDown(self: *Self) bool {
        if (self.cursor_row >= self.line_starts.items.len - 1) return false;
        self.cursor_row += 1;
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }
        return true;
    }

    /// Move cursor left
    pub fn moveCursorLeft(self: *Self) bool {
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
            return true;
        }
        if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = self.getLineLength(self.cursor_row);
            return true;
        }
        return false;
    }

    /// Move cursor right
    pub fn moveCursorRight(self: *Self) bool {
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col < line_len) {
            self.cursor_col += 1;
            return true;
        }
        if (self.cursor_row < self.line_starts.items.len - 1) {
            self.cursor_row += 1;
            self.cursor_col = 0;
            return true;
        }
        return false;
    }

    // ========================================================================
    // Document VTable implementation
    // ========================================================================

    /// Static VTable for Document interface (must be static to avoid dangling pointer)
    pub const vtable = DocumentVTable{
        .deinit = vtableDeinit,
        .getLine = vtableGetLine,
        .getLineCount = vtableGetLineCount,
        .getLineLength = vtableGetLineLength,
        .insertAt = vtableInsertAt,
        .deleteRange = vtableDeleteRange,
        .getCharAt = vtableGetCharAt,
        .getTotalLength = vtableGetTotalLength,
        .isModified = vtableIsModified,
        .clearModified = vtableClearModified,
        .toSlice = vtableToSlice,
        .getCursorRow = vtableGetCursorRow,
        .getCursorCol = vtableGetCursorCol,
        .setCursor = vtableSetCursor,
        .moveCursorUp = vtableMoveCursorUp,
        .moveCursorDown = vtableMoveCursorDown,
        .moveCursorLeft = vtableMoveCursorLeft,
        .moveCursorRight = vtableMoveCursorRight,
    };

    /// Create Document wrapper
    pub fn document(self: *Self) Document {
        return Document.init(self, @constCast(&vtable));
    }

    // VTable implementations
    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableGetLine(ptr: *anyopaque, line: usize) ?[]const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getLine(line);
    }

    fn vtableGetLineCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getLineCount();
    }

    fn vtableGetLineLength(ptr: *anyopaque, line: usize) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getLineLength(line);
    }

    fn vtableInsertAt(ptr: *anyopaque, pos: usize, text: []const u8) DocumentError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.insertAt(pos, text) catch |err| switch (err) {
            error.OutOfMemory => DocumentError.OutOfMemory,
            error.InvalidUtf8 => DocumentError.InvalidUtf8,
        };
    }

    fn vtableDeleteRange(ptr: *anyopaque, range_start: usize, range_end: usize) DocumentError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.deleteRange(range_start, range_end) catch |err| switch (err) {
            error.OutOfMemory => DocumentError.OutOfMemory,
            else => DocumentError.InvalidPosition,
        };
    }

    fn vtableGetCharAt(ptr: *anyopaque, pos: usize) ?u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getCharAt(pos);
    }

    fn vtableGetTotalLength(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getTotalLength();
    }

    fn vtableIsModified(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.isModified();
    }

    fn vtableClearModified(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.clearModified();
    }

    fn vtableToSlice(ptr: *anyopaque, allocator: Allocator) DocumentError![]const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.toSlice(allocator) catch return DocumentError.OutOfMemory;
    }

    fn vtableGetCursorRow(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getCursorRow();
    }

    fn vtableGetCursorCol(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getCursorCol();
    }

    fn vtableSetCursor(ptr: *anyopaque, row: usize, col: usize) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.setCursor(row, col);
    }

    fn vtableMoveCursorUp(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursorUp();
    }

    fn vtableMoveCursorDown(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursorDown();
    }

    fn vtableMoveCursorLeft(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursorLeft();
    }

    fn vtableMoveCursorRight(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursorRight();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MockDocument - init" {
    var mock = MockDocument.init(std.testing.allocator);
    defer mock.deinit();

    try std.testing.expectEqual(@as(usize, 0), mock.getTotalLength());
    try std.testing.expectEqual(@as(usize, 1), mock.getLineCount()); // Empty doc has 1 line
}

test "MockDocument - initContent" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello\nWorld");
    defer mock.deinit();

    try std.testing.expectEqual(@as(usize, 11), mock.getTotalLength());
    try std.testing.expectEqual(@as(usize, 2), mock.getLineCount());
}

test "MockDocument - getLine" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Line 1\nLine 2\nLine 3");
    defer mock.deinit();

    try std.testing.expectEqualStrings("Line 1", mock.getLine(0).?);
    try std.testing.expectEqualStrings("Line 2", mock.getLine(1).?);
    try std.testing.expectEqualStrings("Line 3", mock.getLine(2).?);
    try std.testing.expect(mock.getLine(100) == null);
}

test "MockDocument - insertAt" {
    var mock = MockDocument.init(std.testing.allocator);
    defer mock.deinit();

    try mock.insertAt(0, "Hello");
    try std.testing.expectEqualStrings("Hello", mock.content.items);

    try mock.insertAt(5, " World");
    try std.testing.expectEqualStrings("Hello World", mock.content.items);
    try std.testing.expect(mock.isModified());
}

test "MockDocument - insertAt with newline" {
    var mock = MockDocument.init(std.testing.allocator);
    defer mock.deinit();

    try mock.insertAt(0, "Line 1\nLine 2");
    try std.testing.expectEqual(@as(usize, 2), mock.getLineCount());
}

test "MockDocument - deleteRange" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello World");
    defer mock.deinit();

    try mock.deleteRange(5, 11);
    try std.testing.expectEqualStrings("Hello", mock.content.items);
}

test "MockDocument - cursor operations" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer mock.deinit();

    try std.testing.expect(mock.moveCursorDown());
    try std.testing.expectEqual(@as(usize, 1), mock.getCursorRow());

    try std.testing.expect(mock.moveCursorUp());
    try std.testing.expectEqual(@as(usize, 0), mock.getCursorRow());

    try std.testing.expect(!mock.moveCursorUp()); // Can't go above first line
}

test "MockDocument - cursor left/right" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello");
    defer mock.deinit();

    mock.setCursor(0, 2);
    try std.testing.expectEqual(@as(usize, 2), mock.getCursorCol());

    try std.testing.expect(mock.moveCursorRight());
    try std.testing.expectEqual(@as(usize, 3), mock.getCursorCol());

    try std.testing.expect(mock.moveCursorLeft());
    try std.testing.expectEqual(@as(usize, 2), mock.getCursorCol());
}

test "MockDocument - document interface" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello\nWorld");
    defer mock.deinit();

    var doc = mock.document();
    try std.testing.expectEqual(@as(usize, 2), doc.getLineCount());
    try std.testing.expectEqualStrings("Hello", doc.getLine(0).?);
}

test "MockDocument - clearModified" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello");
    defer mock.deinit();

    try std.testing.expect(!mock.isModified());
    try mock.insertAt(5, " World");
    try std.testing.expect(mock.isModified());
    mock.clearModified();
    try std.testing.expect(!mock.isModified());
}

test "MockDocument - toSlice" {
    var mock = try MockDocument.initContent(std.testing.allocator, "Hello World");
    defer mock.deinit();

    const slice = try mock.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualStrings("Hello World", slice);
}

test "MockDocument - getCharAt" {
    var mock = try MockDocument.initContent(std.testing.allocator, "ABC");
    defer mock.deinit();

    try std.testing.expectEqual(@as(u8, 'A'), mock.getCharAt(0).?);
    try std.testing.expectEqual(@as(u8, 'B'), mock.getCharAt(1).?);
    try std.testing.expectEqual(@as(u8, 'C'), mock.getCharAt(2).?);
    try std.testing.expectEqual(@as(?u8, null), mock.getCharAt(3));
}

test "MockDocument - invalid UTF-8" {
    const invalid = &[_]u8{ 0xFF, 0xFE };
    const result = MockDocument.initContent(std.testing.allocator, invalid);
    try std.testing.expectError(DocumentError.InvalidUtf8, result);
}
