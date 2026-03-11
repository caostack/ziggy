//! Document interface - abstract interface for text storage
//! Allows different storage implementations (GapBuffer, PieceTable, Mock)
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Document errors
pub const DocumentError = error{
    OutOfMemory,
    InvalidPosition,
    InvalidUtf8,
    LineNotFound,
};

/// Document VTable - storage implementations must provide these functions
pub const DocumentVTable = struct {
    /// Clean up resources
    deinit: *const fn (*anyopaque) void,

    /// Get line content by index (0-indexed)
    getLine: *const fn (*anyopaque, usize) ?[]const u8,

    /// Get total number of lines
    getLineCount: *const fn (*anyopaque) usize,

    /// Get line length in bytes
    getLineLength: *const fn (*anyopaque, usize) usize,

    /// Insert text at byte offset
    insertAt: *const fn (*anyopaque, usize, []const u8) DocumentError!void,

    /// Delete text range (start inclusive, end exclusive)
    deleteRange: *const fn (*anyopaque, usize, usize) DocumentError!void,

    /// Get character at byte offset
    getCharAt: *const fn (*anyopaque, usize) ?u8,

    /// Get total document length in bytes
    getTotalLength: *const fn (*anyopaque) usize,

    /// Check if document has unsaved changes
    isModified: *const fn (*anyopaque) bool,

    /// Clear modified flag
    clearModified: *const fn (*anyopaque) void,

    /// Export document as contiguous slice (caller owns memory)
    toSlice: *const fn (*anyopaque, Allocator) DocumentError![]const u8,

    /// Get cursor row (for convenience)
    getCursorRow: *const fn (*anyopaque) usize,

    /// Get cursor column (for convenience)
    getCursorCol: *const fn (*anyopaque) usize,

    /// Set cursor position
    setCursor: *const fn (*anyopaque, usize, usize) void,

    /// Move cursor up
    moveCursorUp: *const fn (*anyopaque) bool,

    /// Move cursor down
    moveCursorDown: *const fn (*anyopaque) bool,

    /// Move cursor left
    moveCursorLeft: *const fn (*anyopaque) bool,

    /// Move cursor right
    moveCursorRight: *const fn (*anyopaque) bool,
};

/// Document interface - wraps any storage implementation
pub const Document = struct {
    ptr: *anyopaque,
    vtable: *const DocumentVTable,

    const Self = @This();

    /// Create Document wrapper from any implementation
    pub fn init(ptr: anytype, vtable: *const DocumentVTable) Self {
        return .{
            .ptr = @ptrCast(@alignCast(ptr)),
            .vtable = vtable,
        };
    }

    /// Clean up resources
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }

    /// Get line content by index
    pub fn getLine(self: Self, line: usize) ?[]const u8 {
        return self.vtable.getLine(self.ptr, line);
    }

    /// Get total number of lines
    pub fn getLineCount(self: Self) usize {
        return self.vtable.getLineCount(self.ptr);
    }

    /// Get line length
    pub fn getLineLength(self: Self, line: usize) usize {
        return self.vtable.getLineLength(self.ptr, line);
    }

    /// Insert text at position
    pub fn insertAt(self: *Self, pos: usize, text: []const u8) DocumentError!void {
        return self.vtable.insertAt(self.ptr, pos, text);
    }

    /// Delete text range
    pub fn deleteRange(self: *Self, start: usize, end: usize) DocumentError!void {
        return self.vtable.deleteRange(self.ptr, start, end);
    }

    /// Get character at position
    pub fn getCharAt(self: Self, pos: usize) ?u8 {
        return self.vtable.getCharAt(self.ptr, pos);
    }

    /// Get total length
    pub fn getTotalLength(self: Self) usize {
        return self.vtable.getTotalLength(self.ptr);
    }

    /// Check if modified
    pub fn isModified(self: Self) bool {
        return self.vtable.isModified(self.ptr);
    }

    /// Clear modified flag
    pub fn clearModified(self: *Self) void {
        self.vtable.clearModified(self.ptr);
    }

    /// Export as slice
    pub fn toSlice(self: Self, allocator: Allocator) DocumentError![]const u8 {
        return self.vtable.toSlice(self.ptr, allocator);
    }

    /// Get cursor row
    pub fn getCursorRow(self: Self) usize {
        return self.vtable.getCursorRow(self.ptr);
    }

    /// Get cursor column
    pub fn getCursorCol(self: Self) usize {
        return self.vtable.getCursorCol(self.ptr);
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, row: usize, col: usize) void {
        self.vtable.setCursor(self.ptr, row, col);
    }

    /// Move cursor up
    pub fn moveCursorUp(self: *Self) bool {
        return self.vtable.moveCursorUp(self.ptr);
    }

    /// Move cursor down
    pub fn moveCursorDown(self: *Self) bool {
        return self.vtable.moveCursorDown(self.ptr);
    }

    /// Move cursor left
    pub fn moveCursorLeft(self: *Self) bool {
        return self.vtable.moveCursorLeft(self.ptr);
    }

    /// Move cursor right
    pub fn moveCursorRight(self: *Self) bool {
        return self.vtable.moveCursorRight(self.ptr);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Mock document for testing the interface
const MockDoc = struct {
    content: []const u8,
    line_count: usize,
    cursor_row: usize,
    cursor_col: usize,

    fn vtable() DocumentVTable {
        return .{
            .deinit = mockDeinit,
            .getLine = mockGetLine,
            .getLineCount = mockGetLineCount,
            .getLineLength = mockGetLineLength,
            .insertAt = mockInsertAt,
            .deleteRange = mockDeleteRange,
            .getCharAt = mockGetCharAt,
            .getTotalLength = mockGetTotalLength,
            .isModified = mockIsModified,
            .clearModified = mockClearModified,
            .toSlice = mockToSlice,
            .getCursorRow = mockGetCursorRow,
            .getCursorCol = mockGetCursorCol,
            .setCursor = mockSetCursor,
            .moveCursorUp = mockMoveCursorUp,
            .moveCursorDown = mockMoveCursorDown,
            .moveCursorLeft = mockMoveCursorLeft,
            .moveCursorRight = mockMoveCursorRight,
        };
    }

    fn mockDeinit(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn mockGetLine(ptr: *anyopaque, line: usize) ?[]const u8 {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        if (line >= self.line_count) return null;
        if (self.line_count == 1) return self.content;
        // Simple implementation for testing
        var current_line: usize = 0;
        var start: usize = 0;
        for (self.content, 0..) |c, i| {
            if (current_line == line) {
                start = i;
                var end: usize = i;
                while (end < self.content.len and self.content[end] != '\n') : (end += 1) {}
                return self.content[start..end];
            }
            if (c == '\n') current_line += 1;
        }
        return null;
    }

    fn mockGetLineCount(ptr: *anyopaque) usize {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        return self.line_count;
    }

    fn mockGetLineLength(ptr: *anyopaque, line: usize) usize {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        const content = self.mockGetLine(ptr, line) orelse return 0;
        return content.len;
    }

    fn mockInsertAt(ptr: *anyopaque, pos: usize, text: []const u8) DocumentError!void {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = pos;
        _ = text;
    }

    fn mockDeleteRange(ptr: *anyopaque, start: usize, end: usize) DocumentError!void {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = start;
        _ = end;
    }

    fn mockGetCharAt(ptr: *anyopaque, pos: usize) ?u8 {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        if (pos >= self.content.len) return null;
        return self.content[pos];
    }

    fn mockGetTotalLength(ptr: *anyopaque) usize {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        return self.content.len;
    }

    fn mockIsModified(ptr: *anyopaque) bool {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        _ = self;
        return false;
    }

    fn mockClearModified(ptr: *anyopaque) void {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        _ = self;
    }

    fn mockToSlice(ptr: *anyopaque, allocator: Allocator) DocumentError![]const u8 {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        return try allocator.dupe(u8, self.content);
    }

    fn mockGetCursorRow(ptr: *anyopaque) usize {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        return self.cursor_row;
    }

    fn mockGetCursorCol(ptr: *anyopaque) usize {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        return self.cursor_col;
    }

    fn mockSetCursor(ptr: *anyopaque, row: usize, col: usize) void {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        self.cursor_row = row;
        self.cursor_col = col;
    }

    fn mockMoveCursorUp(ptr: *anyopaque) bool {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        if (self.cursor_row == 0) return false;
        self.cursor_row -= 1;
        return true;
    }

    fn mockMoveCursorDown(ptr: *anyopaque) bool {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        if (self.cursor_row >= self.line_count - 1) return false;
        self.cursor_row += 1;
        return true;
    }

    fn mockMoveCursorLeft(ptr: *anyopaque) bool {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        if (self.cursor_col == 0) return false;
        self.cursor_col -= 1;
        return true;
    }

    fn mockMoveCursorRight(ptr: *anyopaque) bool {
        const self: *MockDoc = @ptrCast(@alignCast(ptr));
        self.cursor_col += 1;
        return true;
    }
};

test "Document interface - basic operations" {
    var mock = MockDoc{
        .content = "Hello World",
        .line_count = 1,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    var doc = Document.init(&mock, @constCast(&vt));

    try testing.expectEqual(@as(usize, 1), doc.getLineCount());
    try testing.expectEqual(@as(usize, 11), doc.getTotalLength());
    try testing.expectEqual(@as(usize, 0), doc.getCursorRow());
    try testing.expectEqual(@as(usize, 0), doc.getCursorCol());
}

test "Document interface - cursor movement" {
    var mock = MockDoc{
        .content = "Line 1\nLine 2",
        .line_count = 2,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    var doc = Document.init(&mock, @constCast(&vt));

    // Move down
    try testing.expect(doc.moveCursorDown());
    try testing.expectEqual(@as(usize, 1), doc.getCursorRow());

    // Move up
    try testing.expect(doc.moveCursorUp());
    try testing.expectEqual(@as(usize, 0), doc.getCursorRow());

    // Can't move up from first line
    try testing.expect(!doc.moveCursorUp());
}

test "Document interface - get char at" {
    var mock = MockDoc{
        .content = "ABC",
        .line_count = 1,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    const doc = Document.init(&mock, @constCast(&vt));

    try testing.expectEqual(@as(u8, 'A'), doc.getCharAt(0).?);
    try testing.expectEqual(@as(u8, 'B'), doc.getCharAt(1).?);
    try testing.expectEqual(@as(u8, 'C'), doc.getCharAt(2).?);
    try testing.expectEqual(@as(?u8, null), doc.getCharAt(3));
}

test "Document interface - to slice" {
    var mock = MockDoc{
        .content = "Hello",
        .line_count = 1,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    const doc = Document.init(&mock, @constCast(&vt));

    const slice = try doc.toSlice(testing.allocator);
    defer testing.allocator.free(slice);

    try testing.expectEqualStrings("Hello", slice);
}

test "Document interface - set cursor" {
    var mock = MockDoc{
        .content = "Line 1\nLine 2",
        .line_count = 2,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    var doc = Document.init(&mock, @constCast(&vt));

    doc.setCursor(1, 5);
    try testing.expectEqual(@as(usize, 1), doc.getCursorRow());
    try testing.expectEqual(@as(usize, 5), doc.getCursorCol());
}

test "Document interface - cursor left/right" {
    var mock = MockDoc{
        .content = "Hello",
        .line_count = 1,
        .cursor_row = 0,
        .cursor_col = 3,
    };

    const vt = MockDoc.vtable();
    var doc = Document.init(&mock, @constCast(&vt));

    // Move left
    try testing.expect(doc.moveCursorLeft());
    try testing.expectEqual(@as(usize, 2), doc.getCursorCol());

    // Move right
    try testing.expect(doc.moveCursorRight());
    try testing.expectEqual(@as(usize, 3), doc.getCursorCol());
}

test "Document interface - get line" {
    var mock = MockDoc{
        .content = "Line 1\nLine 2\nLine 3",
        .line_count = 3,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    const doc = Document.init(&mock, @constCast(&vt));

    try testing.expectEqualStrings("Line 1", doc.getLine(0).?);
    try testing.expect(doc.getLine(100) == null);
}

test "Document interface - isModified" {
    var mock = MockDoc{
        .content = "Hello",
        .line_count = 1,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    var doc = Document.init(&mock, @constCast(&vt));

    try testing.expect(!doc.isModified());
    doc.clearModified();
}

test "Document interface - getLineLength" {
    var mock = MockDoc{
        .content = "Hello\nWorld",
        .line_count = 2,
        .cursor_row = 0,
        .cursor_col = 0,
    };

    const vt = MockDoc.vtable();
    const doc = Document.init(&mock, @constCast(&vt));

    try testing.expectEqual(@as(usize, 5), doc.getLineLength(0));
}
