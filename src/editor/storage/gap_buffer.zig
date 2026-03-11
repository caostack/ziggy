//! GapBuffer document storage - implements Document interface
//! TDD: Implementation follows tests
const std = @import("std");
const Allocator = std.mem.Allocator;
const document = @import("../core/document.zig");
const DocumentVTable = document.DocumentVTable;
const Document = document.Document;
const DocumentError = document.DocumentError;

/// GapBuffer - text storage with a gap for efficient insertions/deletions
pub const GapBuffer = struct {
    allocator: Allocator,
    data: []u8,
    gap_start: usize,
    gap_end: usize,
    capacity: usize,
    line_starts: []usize,
    line_count: usize,
    line_capacity: usize,
    cursor_row: usize,
    cursor_col: usize,
    modified: bool,

    const Self = @This();

    /// Initialize empty buffer
    pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
        const data = try allocator.alloc(u8, initial_capacity);
        errdefer allocator.free(data);

        const line_capacity: usize = 100;
        const line_starts = try allocator.alloc(usize, line_capacity);
        errdefer allocator.free(line_starts);

        line_starts[0] = 0;

        return .{
            .allocator = allocator,
            .data = data,
            .gap_start = 0,
            .gap_end = initial_capacity,
            .capacity = initial_capacity,
            .line_starts = line_starts,
            .line_count = 1,
            .line_capacity = line_capacity,
            .cursor_row = 0,
            .cursor_col = 0,
            .modified = false,
        };
    }

    /// Initialize with content
    pub fn initContent(allocator: Allocator, content: []const u8) !Self {
        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(content)) {
            return DocumentError.InvalidUtf8;
        }

        var self = try Self.init(allocator, @max(content.len * 2, 4096));
        errdefer self.deinit();

        // Copy content before gap
        @memcpy(self.data[0..content.len], content);
        self.gap_start = content.len;

        // Gap is after content
        self.gap_end = self.capacity;

        // Build line index
        self.line_count = 1;
        self.line_starts[0] = 0;

        for (content, 0..) |c, i| {
            if (c == '\n') {
                if (self.line_count >= self.line_capacity) {
                    try self.growLineCapacity();
                }
                self.line_starts[self.line_count] = i + 1;
                self.line_count += 1;
            }
        }

        // Position cursor at end of content (same as gap position)
        self.cursor_row = if (self.line_count > 0) self.line_count - 1 else 0;
        if (self.line_count > 0) {
            const last_line_start = self.line_starts[self.cursor_row];
            self.cursor_col = self.gap_start - last_line_start;
        }

        return self;
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
        self.allocator.free(self.line_starts);
    }

    /// Get content length (excluding gap)
    pub fn length(self: *const Self) usize {
        return self.gap_start + (self.capacity - self.gap_end);
    }

    /// Get line content by index
    pub fn getLine(self: *const Self, line_num: usize) ?[]const u8 {
        if (line_num >= self.line_count) return null;

        const gap_size = self.gap_end - self.gap_start;

        // line_starts stores logical offsets
        const logical_start = self.line_starts[line_num];
        const logical_end = if (line_num + 1 < self.line_count)
            self.line_starts[line_num + 1]
        else
            self.length();

        // Convert logical to physical offsets
        const phys_start = if (logical_start < self.gap_start)
            logical_start
        else
            logical_start + gap_size;

        const phys_end = if (logical_end <= self.gap_start)
            logical_end
        else
            logical_end + gap_size;

        if (phys_start >= phys_end) return "";
        return self.data[phys_start..phys_end];
    }

    /// Get total number of lines
    pub fn getLineCount(self: *const Self) usize {
        return self.line_count;
    }

    /// Get length of a specific line in bytes
    pub fn getLineLength(self: *const Self, line_num: usize) usize {
        if (line_num >= self.line_count) {
            return 0;
        }
        const start = self.line_starts[line_num];
        const end = if (line_num + 1 < self.line_count)
            self.line_starts[line_num + 1]
        else
            self.length();
        
        if (end <= start) return 0;
        // Last line doesn't have trailing newline
        if (line_num == self.line_count - 1) {
            return end - start;
        }
        return end - start - 1; // -1 for newline
    }

    /// Insert text at cursor position
    pub fn insert(self: *Self, bytes: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(bytes)) {
            return DocumentError.InvalidUtf8;
        }

        // Ensure gap is at cursor position before inserting
        self.moveGapToCursor();

        const needed = bytes.len;
        const available = self.gap_end - self.gap_start;

        if (needed > available) {
            const new_capacity = @max(self.capacity * 2, needed * 2);
            try self.grow(new_capacity);
        }

        // Insert into gap
        @memcpy(self.data[self.gap_start..][0..needed], bytes);
        self.gap_start += needed;
        self.modified = true;

        // Update cursor position and line tracking
        if (bytes.len == 1 and bytes[0] == '\n') {
            // Newline inserted - need to update line_starts
            if (self.line_count >= self.line_capacity) {
                try self.growLineCapacity();
            }

            // line_starts stores logical offsets (position in content, ignoring gap)
            // After moveGapToCursor() and inserting newline, the logical offset of new line
            // = logical offset of cursor + 1 (the newline we just inserted)
            // Since gap is at cursor, logical offset of cursor = gap_start - bytes.len + bytes.len = gap_start
            // But we want the position AFTER the newline, which is gap_start
            const new_line_logical = self.gap_start;
            const insert_at_row = self.cursor_row + 1;

            // Shift line_starts and add 1 to offsets after insertion point (for the newline char)
            var i = self.line_count;
            while (i > insert_at_row) : (i -= 1) {
                self.line_starts[i] = self.line_starts[i - 1] + 1;
            }
            self.line_starts[insert_at_row] = new_line_logical;
            self.line_count += 1;

            self.cursor_row += 1;
            self.cursor_col = 0;
        } else {
            self.cursor_col += @as(usize, bytes.len);
        }
    }

    /// Delete character before cursor
    pub fn delete(self: *Self) bool {
        if (self.gap_start == 0) return false;

        const utf8_len = self.findUtf8CharBefore(self.gap_start) orelse return false;
        self.gap_start -= utf8_len;

        const deleted_byte = self.data[self.gap_start];
        if (deleted_byte == '\n') {
            // Deleted a newline
            if (self.cursor_row > 0) {
                self.cursor_row -= 1;
                if (self.cursor_row > 0) {
                    self.cursor_col = self.gap_start - self.line_starts[self.cursor_row];
                } else {
                    self.cursor_col = self.gap_start;
                }
            }
            if (self.line_count > 1) {
                self.line_count -= 1;
            }
        } else {
            if (self.cursor_col >= utf8_len) {
                self.cursor_col -= utf8_len;
            }
        }

        return true;
    }

    /// Move cursor up one row
    pub fn moveUp(self: *Self) bool {
        if (self.cursor_row == 0) return false;

        self.cursor_row -= 1;
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }

        return true;
    }

    /// Move cursor down one row
    pub fn moveDown(self: *Self) bool {
        if (self.cursor_row >= self.line_count - 1) return false;

        self.cursor_row += 1;
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }

        return true;
    }

    /// Move cursor left one character
    pub fn moveLeft(self: *Self) bool {
        if (self.cursor_col == 0) {
            if (self.cursor_row == 0) return false;
            // Move to end of previous line
            self.cursor_row -= 1;
            self.cursor_col = self.getLineLength(self.cursor_row);
        } else {
            self.cursor_col -= 1;
        }

        return true;
    }

    /// Move cursor right one character
    pub fn moveRight(self: *Self) bool {
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col >= line_len) {
            // At end of line, try to move to next line
            if (self.cursor_row >= self.line_count - 1) return false;
            self.cursor_row += 1;
            self.cursor_col = 0;
        } else {
            self.cursor_col += 1;
        }

        return true;
    }

    /// Convert gap buffer to contiguous string (for saving)
    pub fn toSlice(self: *const Self, allocator: Allocator) ![]const u8 {
        const total_len = self.length();
        const result = try allocator.alloc(u8, total_len);

        // Copy content before gap
        @memcpy(result[0..self.gap_start], self.data[0..self.gap_start]);

        // Copy content after gap
        const after_gap = self.data[self.gap_end..];
        @memcpy(result[self.gap_start..][0..after_gap.len], after_gap);

        return result;
    }

    /// Check if modified
    pub fn isModified(self: *const Self) bool {
        return self.modified;
    }

    /// Clear modified flag
    pub fn clearModified(self: *Self) void {
        self.modified = false;
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
        self.cursor_row = @min(row, self.line_count -| 1);
        const line_len = self.getLineLength(self.cursor_row);
        self.cursor_col = @min(col, line_len);
    }

    /// Calculate byte offset of cursor position in document
    fn cursorToByteOffset(self: *const Self) usize {
        if (self.cursor_row >= self.line_count) return self.gap_start;

        const line_start = self.line_starts[self.cursor_row];
        // Adjust for gap if line_start is after gap
        const adjusted_line_start = if (line_start < self.gap_start)
            line_start
        else
            line_start + (self.gap_end - self.gap_start);

        return adjusted_line_start + self.cursor_col;
    }

    /// Move gap to current cursor position
    fn moveGapToCursor(self: *Self) void {
        const target_offset = self.cursorToByteOffset();
        const gap_size = self.gap_end - self.gap_start;

        if (target_offset < self.gap_start) {
            // Move gap left: copy data from target_offset to gap_start to after gap
            const move_size = self.gap_start - target_offset;
            const src = self.data[target_offset..self.gap_start];
            const dst = self.data[self.gap_end - move_size .. self.gap_end];
            @memcpy(dst, src);
            self.gap_start = target_offset;
            self.gap_end = target_offset + gap_size;
        } else if (target_offset > self.gap_start) {
            // Move gap right: copy data from gap_end to target to before gap
            const adjusted_target = target_offset - gap_size; // target in pre-gap coordinates
            if (adjusted_target > self.gap_start) {
                const move_size = adjusted_target - self.gap_start;
                const src = self.data[self.gap_end .. self.gap_end + move_size];
                const dst = self.data[self.gap_start .. self.gap_start + move_size];
                @memcpy(dst, src);
                self.gap_start = adjusted_target;
                self.gap_end = adjusted_target + gap_size;
            }
        }
    }

    /// Grow buffer capacity
    fn grow(self: *Self, new_capacity: usize) !void {
        const new_data = try self.allocator.alloc(u8, new_capacity);
        errdefer self.allocator.free(new_data);

        // Copy data before gap
        @memcpy(new_data[0..self.gap_start], self.data[0..self.gap_start]);

        // Copy data after gap
        const after_gap = self.data[self.gap_end..];
        const new_gap_end = new_capacity - (self.capacity - self.gap_end);
        @memcpy(new_data[new_gap_end..][0..after_gap.len], after_gap);

        // Update buffer
        self.allocator.free(self.data);
        self.data = new_data;
        self.gap_end = new_gap_end;
        self.capacity = new_capacity;
    }

    /// Grow line tracking capacity
    fn growLineCapacity(self: *Self) !void {
        const new_cap = self.line_capacity * 2;
        const new_starts = try self.allocator.realloc(self.line_starts, new_cap);
        self.line_starts = new_starts;
        self.line_capacity = new_cap;
    }

    /// Find the length of UTF-8 character before a position
    fn findUtf8CharBefore(self: *const Self, pos: usize) ?usize {
        if (pos == 0) return null;

        // Scan backwards for valid UTF-8 start byte
        var i: usize = pos - 1;
        while (i > 0) : (i -= 1) {
            const byte = self.data[i];
            // UTF-8 start bytes: 0xxxxxxx, 110xxxxx, 1110xxxx, 11110xxx
            if (byte & 0xC0 != 0x80) {
                // Found start byte, validate sequence
                const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch return null;
                if (i + seq_len == pos) {
                    return seq_len;
                }
                return null;
            }
        }

        // Check first byte
        const byte = self.data[0];
        const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch return null;
        if (seq_len == pos) return seq_len;
        return null;
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
        _ = pos;
        try self.insert(text);
    }

    fn vtableDeleteRange(ptr: *anyopaque, start: usize, end: usize) DocumentError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = start;
        _ = end;
        // TODO: Implement range deletion
    }

    fn vtableGetCharAt(ptr: *anyopaque, pos: usize) ?u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (pos >= self.gap_start) {
            // Position is in or after gap
            const adjusted = pos + (self.gap_end - self.gap_start);
            if (adjusted >= self.data.len) return null;
            return self.data[adjusted];
        } else {
            // Position is before gap
            if (pos >= self.gap_start) return null;
            return self.data[pos];
        }
    }

    fn vtableGetTotalLength(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.length();
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
        return self.moveUp();
    }

    fn vtableMoveCursorDown(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveDown();
    }

    fn vtableMoveCursorLeft(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveLeft();
    }

    fn vtableMoveCursorRight(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveRight();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "GapBuffer.init - creates empty buffer" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 0), buf.gap_start);
    try std.testing.expectEqual(@as(usize, 100), buf.gap_end);
    try std.testing.expectEqual(@as(usize, 1), buf.line_count);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_col);
}

test "GapBuffer.initContent - creates buffer with content" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello World");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 11), buf.gap_start);
    try std.testing.expectEqual(@as(usize, 1), buf.line_count);
    try std.testing.expect(!buf.modified);
}

test "GapBuffer.initContent - tracks multiple lines" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2\nLine 3");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 3), buf.line_count);
}

test "GapBuffer.initContent - empty content" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 0), buf.gap_start);
    try std.testing.expectEqual(@as(usize, 1), buf.line_count);
}

test "GapBuffer.getLine - single line" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello World");
    defer buf.deinit();

    const line = buf.getLine(0);
    try std.testing.expect(line != null);
    try std.testing.expectEqualStrings("Hello World", line.?);
}

test "GapBuffer.getLine - multiple lines" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2\nLine 3");
    defer buf.deinit();

    try std.testing.expectEqualStrings("Line 1\n", (buf.getLine(0) orelse ""));
    try std.testing.expectEqualStrings("Line 2\n", (buf.getLine(1) orelse ""));
    try std.testing.expectEqualStrings("Line 3", (buf.getLine(2) orelse ""));
}

test "GapBuffer.getLine - out of bounds returns null" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello");
    defer buf.deinit();

    try std.testing.expect(buf.getLine(0) != null);
    try std.testing.expect(buf.getLine(1) == null);
    try std.testing.expect(buf.getLine(100) == null);
}

test "GapBuffer.getLineCount - correct count" {
    var buf1 = try GapBuffer.initContent(std.testing.allocator, "");
    defer buf1.deinit();
    try std.testing.expectEqual(@as(usize, 1), buf1.getLineCount());

    var buf2 = try GapBuffer.initContent(std.testing.allocator, "One\nTwo\nThree");
    defer buf2.deinit();
    try std.testing.expectEqual(@as(usize, 3), buf2.getLineCount());
}

test "GapBuffer.getLineLength - correct lengths" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello\nWorld");
    defer buf.deinit();

    try std.testing.expectEqual(@as(usize, 6), buf.getLineLength(0)); // "Hello\n"
    try std.testing.expectEqual(@as(usize, 5), buf.getLineLength(1)); // "World"
}

test "GapBuffer.insert - appends to empty buffer" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    try buf.insert("Hello");
    try std.testing.expectEqual(@as(usize, 5), buf.gap_start);
    try std.testing.expect(buf.modified);
}

test "GapBuffer.insert - multiple inserts" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    try buf.insert("Hello");
    try buf.insert(" ");
    try buf.insert("World");

    const content = try buf.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("Hello World", content);
}

test "GapBuffer.insert - newline adds line" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    try buf.insert("Line 1\n");
    try std.testing.expectEqual(@as(usize, 2), buf.line_count);
    try std.testing.expectEqual(@as(usize, 1), buf.cursor_row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_col);
}

test "GapBuffer.insert - UTF-8 characters" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    try buf.insert("Hello");
    try buf.insert(" 世界");
    try buf.insert(" 🚀");

    const content = try buf.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("Hello 世界 🚀", content);
}

test "GapBuffer.insert - rejects invalid UTF-8" {
    var buf = try GapBuffer.init(std.testing.allocator, 100);
    defer buf.deinit();

    const invalid = [_]u8{ 0xFF, 0xFE };
    try std.testing.expectError(DocumentError.InvalidUtf8, buf.insert(&invalid));
}

test "GapBuffer.insert - grows buffer when needed" {
    var buf = try GapBuffer.init(std.testing.allocator, 10);
    defer buf.deinit();

    // Insert more than capacity
    try buf.insert("This is a very long string that exceeds initial capacity");
    try std.testing.expect(buf.capacity > 10);
}

test "GapBuffer.delete - removes last character" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello");
    defer buf.deinit();

    try std.testing.expect(buf.delete());
    try std.testing.expectEqual(@as(usize, 4), buf.gap_start);
    try std.testing.expect(buf.modified);
}

test "GapBuffer.delete - at start returns false" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello");
    defer buf.deinit();

    buf.gap_start = 0;
    try std.testing.expect(!buf.delete());
}

test "GapBuffer.moveUp - from second line" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer buf.deinit();

    buf.cursor_row = 1;
    buf.cursor_col = 3;

    try std.testing.expect(buf.moveUp());
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_row);
}

test "GapBuffer.moveUp - from first line returns false" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer buf.deinit();

    buf.cursor_row = 0;
    try std.testing.expect(!buf.moveUp());
}

test "GapBuffer.moveDown - from first line" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer buf.deinit();

    buf.cursor_row = 0;
    try std.testing.expect(buf.moveDown());
    try std.testing.expectEqual(@as(usize, 1), buf.cursor_row);
}

test "GapBuffer.moveDown - from last line returns false" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer buf.deinit();

    buf.cursor_row = 1;
    try std.testing.expect(!buf.moveDown());
}

test "GapBuffer.document - implements Document interface" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello\nWorld");
    defer buf.deinit();

    var doc = buf.document();

    try std.testing.expectEqual(@as(usize, 2), doc.getLineCount());
    try std.testing.expectEqualStrings("Hello\n", doc.getLine(0).?);
    try std.testing.expectEqualStrings("World", doc.getLine(1).?);
}

test "GapBuffer.document - cursor operations" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer buf.deinit();

    var doc = buf.document();

    try std.testing.expectEqual(@as(usize, 0), doc.getCursorRow());

    try std.testing.expect(doc.moveCursorDown());
    try std.testing.expectEqual(@as(usize, 1), doc.getCursorRow());

    try std.testing.expect(doc.moveCursorUp());
    try std.testing.expectEqual(@as(usize, 0), doc.getCursorRow());
}

test "GapBuffer.delete - removes newline" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "A\nB");
    defer buf.deinit();

    // Position cursor after newline
    buf.cursor_row = 1;
    buf.cursor_col = 0;
    buf.gap_start = 2; // After "A\n"

    try std.testing.expect(buf.delete());
    try std.testing.expectEqual(@as(usize, 1), buf.line_count);
}

test "GapBuffer.moveLeft - wraps to previous line" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "AB\nCD");
    defer buf.deinit();

    buf.cursor_row = 1;
    buf.cursor_col = 0;

    try std.testing.expect(buf.moveLeft());
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_row);
}

test "GapBuffer.moveRight - wraps to next line" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "AB\nCD");
    defer buf.deinit();

    buf.cursor_row = 0;
    buf.cursor_col = 2; // At end of first line

    try std.testing.expect(buf.moveRight());
    try std.testing.expectEqual(@as(usize, 1), buf.cursor_row);
    try std.testing.expectEqual(@as(usize, 0), buf.cursor_col);
}

test "GapBuffer.toSlice - with gap in middle" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello World");
    defer buf.deinit();

    // Insert to create gap movement
    try buf.insert("X");

    const content = try buf.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("Hello WorldX", content);
}

test "GapBuffer.clearModified" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "Hello");
    defer buf.deinit();

    try buf.insert("X");
    try std.testing.expect(buf.isModified());

    buf.clearModified();
    try std.testing.expect(!buf.isModified());
}

test "GapBuffer.setCursor - clamps to valid range" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "AB\nCD");
    defer buf.deinit();

    // Set beyond bounds
    buf.setCursor(100, 100);
    try std.testing.expectEqual(@as(usize, 1), buf.cursor_row);
    try std.testing.expectEqual(@as(usize, 2), buf.cursor_col);
}

test "GapBuffer.getCharAt - handles gap correctly" {
    var buf = try GapBuffer.initContent(std.testing.allocator, "ABC");
    defer buf.deinit();

    try std.testing.expectEqual(@as(u8, 'A'), buf.document().getCharAt(0).?);
    try std.testing.expectEqual(@as(u8, 'B'), buf.document().getCharAt(1).?);
    try std.testing.expectEqual(@as(u8, 'C'), buf.document().getCharAt(2).?);
}
