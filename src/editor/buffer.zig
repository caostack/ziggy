//! UTF-8 text buffer using gap buffer data structure
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BufferError = error{
    OutOfMemory,
    InvalidUtf8,
    CursorOutOfBounds,
};

pub const Buffer = struct {
    allocator: Allocator,
    data: []u8, // Raw UTF-8 bytes
    gap_start: usize, // Start of gap (cursor position)
    gap_end: usize, // End of gap
    capacity: usize, // Total allocated capacity

    // UTF-8 line tracking for rendering
    line_starts: []usize, // Byte offsets of line starts
    line_count: usize, // Number of lines
    line_capacity: usize, // Capacity of line_starts array

    // Cursor position in (row, col) coordinates
    cursor_row: usize,
    cursor_col: usize,

    pub fn init(allocator: Allocator, initial_capacity: usize) !Buffer {
        const data = try allocator.alloc(u8, initial_capacity);
        errdefer allocator.free(data);

        // Initialize line tracking with capacity for 100 lines
        const line_capacity = 100;
        const line_starts = try allocator.alloc(usize, line_capacity);
        errdefer allocator.free(line_starts);

        line_starts[0] = 0; // First line starts at byte 0

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
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.data);
        self.allocator.free(self.line_starts);
    }

    /// Insert UTF-8 sequence at cursor position
    pub fn insert(self: *Buffer, bytes: []const u8) !void {
        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(bytes)) {
            return BufferError.InvalidUtf8;
        }

        // Check if gap has space
        const needed = bytes.len;
        const available = self.gap_end - self.gap_start;

        if (needed > available) {
            // Grow buffer (typically 2x or enough to fit)
            const new_capacity = @max(self.capacity * 2, self.capacity + needed * 2);
            try self.grow(new_capacity);
        }

        // Insert into gap
        @memcpy(self.data[self.gap_start..][0..needed], bytes);
        self.gap_start += needed;

        // Update line tracking if newline inserted
        if (bytes.len == 1 and bytes[0] == '\n') {
            // Grow line tracking if needed
            if (self.line_count >= self.line_capacity) {
                const new_capacity = self.line_capacity * 2;
                const new_line_starts = try self.allocator.realloc(self.line_starts, new_capacity);
                self.line_starts = new_line_starts;
                self.line_capacity = new_capacity;
            }

            self.line_starts[self.line_count] = self.gap_start;
            self.line_count += 1;
            self.cursor_row += 1;
            self.cursor_col = 0;
        } else {
            // Update column (in bytes, not graphemes)
            self.cursor_col += bytes.len;
        }
    }

    /// Delete character before cursor
    pub fn delete(self: *Buffer) bool {
        if (self.gap_start == 0) return false;

        // Find previous UTF-8 sequence start
        const utf8_len = self.findUtf8CharBefore(self.gap_start) orelse return false;
        self.gap_start -= utf8_len;

        // Update cursor position
        const deleted_byte = self.data[self.gap_start];
        if (deleted_byte == '\n') {
            // Deleted a newline
            if (self.cursor_row > 0) {
                self.cursor_row -= 1;
                // Move cursor to end of previous line
                if (self.cursor_row > 0) {
                    self.cursor_col = self.gap_start - self.line_starts[self.cursor_row];
                } else {
                    self.cursor_col = self.gap_start;
                }
            }
            // Remove line from tracking
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

    /// Get character at cursor (as UTF-8 slice)
    pub fn getCharAtCursor(self: *const Buffer) ?[]const u8 {
        if (self.gap_end >= self.data.len) return null;
        const char_len = std.unicode.utf8ByteSequenceLength(self.data[self.gap_end]) catch return null;
        return self.data[self.gap_end..][0..char_len];
    }

    /// Move cursor up one row
    pub fn moveUp(self: *Buffer) bool {
        if (self.cursor_row == 0) return false;

        self.cursor_row -= 1;
        // Clamp column to line length
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }

        return true;
    }

    /// Move cursor down one row
    pub fn moveDown(self: *Buffer) bool {
        if (self.cursor_row >= self.line_count - 1) return false;

        self.cursor_row += 1;
        // Clamp column to line length
        const line_len = self.getLineLength(self.cursor_row);
        if (self.cursor_col > line_len) {
            self.cursor_col = line_len;
        }

        return true;
    }

    /// Move cursor left one character
    pub fn moveLeft(self: *Buffer) bool {
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
    pub fn moveRight(self: *Buffer) bool {
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

    /// Get line at current cursor position
    pub fn getLine(self: *const Buffer, line_num: usize) ?[]const u8 {
        if (line_num >= self.line_count) return null;

        const start = self.line_starts[line_num];
        const end = if (line_num + 1 < self.line_count)
            self.line_starts[line_num + 1]
        else
            self.gap_start; // Last line goes to cursor

        // Adjust for gap
        const adjusted_start = if (start < self.gap_start) start else start + (self.gap_end - self.gap_start);
        const adjusted_end = if (end < self.gap_start) end else end + (self.gap_end - self.gap_start);

        if (adjusted_start >= adjusted_end) return "";
        return self.data[adjusted_start..adjusted_end];
    }

    /// Get total number of lines
    pub fn getLineCount(self: *const Buffer) usize {
        return self.line_count;
    }

    /// Get length of a specific line in bytes
    pub fn getLineLength(self: *const Buffer, line_num: usize) usize {
        if (line_num >= self.line_count - 1) {
            // Last line
            return self.gap_start - self.line_starts[line_num];
        }
        return self.line_starts[line_num + 1] - self.line_starts[line_num] - 1; // -1 for newline
    }

    /// Convert gap buffer to contiguous string (for saving)
    pub fn toSlice(self: *const Buffer) []const u8 {
        // For simplicity, we'll just return data before gap
        // A real implementation would combine data before and after gap
        return self.data[0..self.gap_start];
    }

    fn grow(self: *Buffer, new_capacity: usize) !void {
        const new_data = try self.allocator.alloc(u8, new_capacity);
        errdefer self.allocator.free(new_data);

        // Copy data before gap
        @memcpy(new_data[0..self.gap_start], self.data[0..self.gap_start]);

        // Copy data after gap
        const after_gap = self.data[self.gap_end..];
        const new_gap_end = new_capacity - (self.capacity - self.gap_end);
        @memcpy(new_data[new_gap_end..], after_gap);

        // Update buffer
        self.allocator.free(self.data);
        self.data = new_data;
        self.gap_end = new_gap_end;
        self.capacity = new_capacity;
    }

    fn findUtf8CharBefore(self: *const Buffer, pos: usize) ?usize {
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
};

test "buffer insert ascii" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    try buffer.insert("Hello");
    try buffer.insert(" ");
    try buffer.insert("World");

    try std.testing.expectEqual(@as(usize, 11), buffer.gap_start);
    try std.testing.expectEqual(@as(usize, 1), buffer.lines.items.len);
}

test "buffer insert newlines" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    try buffer.insert("Line 1\n");
    try buffer.insert("Line 2\n");
    try buffer.insert("Line 3");

    try std.testing.expectEqual(@as(usize, 3), buffer.lines.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor_row);
}

test "buffer delete" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    try buffer.insert("Hello");

    const deleted = buffer.delete();
    try std.testing.expect(deleted);

    try std.testing.expectEqual(@as(usize, 4), buffer.gap_start);
}

test "buffer cursor movement" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    try buffer.insert("AB\nCD");

    // Should be on row 1, col 0 after newline
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor_row);
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor_col);

    // Move up
    _ = buffer.moveUp();
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor_row);

    // Move down
    _ = buffer.moveDown();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor_row);
}

test "utf8 validation" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    // Valid UTF-8
    try buffer.insert("Hello");
    try buffer.insert(" 世界"); // Chinese characters
    try buffer.insert("🚀"); // Emoji

    // Invalid UTF-8 should fail
    const invalid = [_]u8{ 0xFF, 0xFE };
    try std.testing.expectError(BufferError.InvalidUtf8, buffer.insert(&invalid));
}

test "buffer get line" {
    var buffer = try Buffer.init(std.testing.allocator, 100);
    defer buffer.deinit();

    try buffer.insert("First line\n");
    try buffer.insert("Second line");

    const line0 = buffer.getLine(0);
    try std.testing.expect(line0 != null);
    try std.testing.expectEqualStrings("First line\n", line0.?);

    const line1 = buffer.getLine(1);
    try std.testing.expect(line1 != null);
    try std.testing.expectEqualStrings("Second line", line1.?);
}
