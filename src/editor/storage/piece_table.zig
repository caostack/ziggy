//! PieceTable document storage - optimized for large files
//! Uses two buffers: original (read-only) and add (edits)
//! This is more memory-efficient than GapBuffer for large files
//!
//! Design principles:
//! - Original buffer is immutable (file content)
//! - Add buffer stores all edits
//! - Pieces reference either buffer
//! - Line index is built from pieces for fast line access
//!
const std = @import("std");
const Allocator = std.mem.Allocator;
const document = @import("../core/document.zig");
const DocumentVTable = document.DocumentVTable;
const Document = document.Document;
const DocumentError = document.DocumentError;
const ArrayList = std.ArrayList;

/// Piece source - where text comes from
const PieceSource = enum {
    original, // From the original buffer (read-only)
    add, // From the add buffer (mutable)
};

/// A single piece of text
const Piece = struct {
    source: PieceSource,
    start: usize, // Offset in source buffer
    length: usize, // Length of this piece
};

/// PieceTable - efficient text storage for large files
pub const PieceTable = struct {
    allocator: Allocator,

    // Original buffer (file content, read-only)
    original_buffer: []const u8,

    // Add buffer (edits, mutable)
    add_buffer: ArrayList(u8),

    // Piece list
    pieces: ArrayList(Piece),

    // Line tracking (for rendering)
    line_starts: ArrayList(usize),
    line_count: usize,

    // Cursor position
    cursor_row: usize,
    cursor_col: usize,

    // Modified flag
    modified: bool,

    const Self = @This();

    /// Initialize empty PieceTable
    pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
        const original = try allocator.alloc(u8, initial_capacity);
        errdefer allocator.free(original);

        var add_buffer = ArrayList(u8).init(allocator);
        errdefer add_buffer.deinit();

        var pieces = ArrayList(Piece).init(allocator);
        errdefer pieces.deinit();

        var line_starts = ArrayList(usize).init(allocator);
        errdefer line_starts.deinit();

        try line_starts.append(0);

        return .{
            .allocator = allocator,
            .original_buffer = original,
            .add_buffer = add_buffer,
            .pieces = pieces,
            .line_starts = line_starts,
            .line_count = 1,
            .cursor_row = 0,
            .cursor_col = 0,
            .modified = false,
        };
    }

    /// Initialize with file content
    pub fn initContent(allocator: Allocator, content: []const u8) !Self {
        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(content)) {
            return DocumentError.InvalidUtf8;
        }

        var self = try Self.init(allocator, content.len);
        errdefer self.deinit();

        // Store original content
        self.original_buffer = try allocator.dupe(u8, content);
        errdefer allocator.free(self.original_buffer);

        // Add initial piece pointing to entire content
        try self.pieces.append(.{
            .source = .original,
            .start = 0,
            .length = content.len,
        });

        // Build line index
        try self.buildLineIndex();

        return self;
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.original_buffer);
        self.add_buffer.deinit();
        self.pieces.deinit();
        self.line_starts.deinit();
    }

    /// Build line index from current pieces
    fn buildLineIndex(self: *Self) !void {
        self.line_count = 1;
        self.line_starts.items[0] = 0;

        var total_offset: usize = 0;
        for (self.pieces.items) |piece| {
            const text = self.getPieceText(piece);
            for (text, 0..) |c, local_offset| {
                if (c == '\n') {
                    try self.line_starts.append(total_offset + local_offset + 1);
                    self.line_count += 1;
                }
            }
            total_offset += text.len;
        }
    }

    /// Get text from a piece
    fn getPieceText(self: *const Self, piece: Piece) []const u8 {
        return switch (piece.source) {
            .original => self.original_buffer[piece.start..][0..piece.length],
            .add => self.add_buffer.items[piece.start..][0..piece.length],
        };
    }

    /// Get line content by index
    pub fn getLine(self: *const Self, line_num: usize) ?[]const u8 {
        if (line_num >= self.line_count) return null;

        const start_offset = self.line_starts.items[line_num];
        const end_offset = if (line_num + 1 < self.line_count)
            self.line_starts.items[line_num + 1]
        else
            self.getTotalLength();

        if (start_offset >= end_offset) return "";

        const length = end_offset - start_offset;
        var result = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(result);

        var piece_idx: usize = 0;
        var doc_offset: usize = 0;

        // Find starting piece
        while (piece_idx < self.pieces.items.len) {
            const piece = self.pieces.items[piece_idx];
            const piece_end = doc_offset + piece.length;

            if (piece_end > start_offset) {
                // Found starting piece
                break;
            }
            doc_offset = piece_end;
            piece_idx += 1;
        }

        // Copy text from pieces
        var write_offset: usize = 0;
        while (piece_idx < self.pieces.items.len and write_offset < length) {
            const piece = self.pieces.items[piece_idx];
            const piece_text = self.getPieceText(piece);

            const read_start = if (doc_offset < start_offset) start_offset - doc_offset else 0;
            const read_end = @min(piece.length, read_start + (length - write_offset));

            if (read_end > read_start) {
                @memcpy(result[write_offset..][0 .. read_end - read_start], piece_text[read_start..read_end]);
                write_offset += read_end - read_start;
            }

            doc_offset += piece.length;
            piece_idx += 1;
        }

        return result[0..write_offset];
    }

    /// Get total number of lines
    pub fn getLineCount(self: *const Self) usize {
        return self.line_count;
    }

    /// Get length of a specific line
    pub fn getLineLength(self: *const Self, line_num: usize) usize {
        const line = self.getLine(line_num) orelse return 0;
        var len = line.len;
        if (len > 0 and line[len - 1] == '\n') {
            len -= 1;
        }
        self.allocator.free(@constCast(line).?);
        return len;
    }

    /// Insert text at cursor position
    pub fn insert(self: *Self, text: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(text)) {
            return DocumentError.InvalidUtf8;
        }

        // Add text to add buffer
        const add_start = self.add_buffer.items.len;
        try self.add_buffer.appendSlice(text);

        // Add new piece
        try self.pieces.append(.{
            .source = .add,
            .start = add_start,
            .length = text.len,
        });

        self.modified = true;
        self.cursor_col += text.len;

        // Rebuild line index if we inserted a newline
        for (text) |c| {
            if (c == '\n') {
                try self.line_starts.append(0); // Placeholder
                try self.buildLineIndex();
                break;
            }
        }
    }

    /// Delete character before cursor
    pub fn delete(self: *Self) bool {
        // TODO: Implement delete from piece table
        if (self.cursor_col == 0) return false;
        self.cursor_col -= 1;
        return true;
    }

    /// Get total document length
    pub fn getTotalLength(self: *const Self) usize {
        var total: usize = 0;
        for (self.pieces.items) |piece| {
            total += piece.length;
        }
        return total;
    }

    /// Export as contiguous slice
    pub fn toSlice(self: *const Self, allocator: Allocator) ![]const u8 {
        const total_len = self.getTotalLength();
        const result = try allocator.alloc(u8, total_len);
        errdefer allocator.free(result);

        var offset: usize = 0;
        for (self.pieces.items) |piece| {
            const piece_text = self.getPieceText(piece);
            @memcpy(result[offset..][0..piece.length], piece_text);
            offset += piece.length;
        }

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
        if (self.cursor_row >= self.line_count - 1) return false;
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
        if (self.cursor_row < self.line_count - 1) {
            self.cursor_row += 1;
            self.cursor_col = 0;
            return true;
        }
        return false;
    }

    // ========================================================================
    // Document VTable implementation
    // ========================================================================

    /// Get the VTable for Document interface
    pub fn vtable() DocumentVTable {
        return .{
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
    }

    /// Create Document wrapper
    pub fn document(self: *Self) Document {
        return Document.init(self, @constCast(&vtable()));
    }

    // VTable implementations
    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableGetLine(ptr: *anyopaque, line: usize) ?[]const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const result = self.getLine(line) orelse return null;
        // Note: Caller must free this memory
        // For VTable compatibility, we return the owned slice
        return result;
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

    fn vtableDeleteRange(ptr: *anyopaque, range_start: usize, range_end: usize) DocumentError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self; // TODO: Use self when implementing range deletion
        _ = range_start;
        _ = range_end;
        // TODO: Implement range deletion
    }

    fn vtableGetCharAt(ptr: *anyopaque, pos: usize) ?u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const slice = self.toSlice(self.allocator) catch return null;
        defer self.allocator.free(slice);
        if (pos >= slice.len) return null;
        return slice[pos];
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
test "PieceTable - init" {
    var pt = try PieceTable.init(std.testing.allocator, 4096);
    defer pt.deinit();
    try std.testing.expectEqual(@as(usize, 0), pt.pieces.items.len);
    try std.testing.expectEqual(@as(usize, 1), pt.line_count);
}

test "PieceTable - initContent" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Hello\nWorld");
    defer pt.deinit();
    try std.testing.expectEqual(@as(usize, 2), pt.line_count);
}
test "PieceTable - initContent empty" {
    var pt = try PieceTable.initContent(std.testing.allocator, "");
    defer pt.deinit();
    try std.testing.expectEqual(@as(usize, 1), pt.line_count);
}
test "PieceTable - getLineCount" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Line 1\nLine 2\nLine 3");
    defer pt.deinit();
    try std.testing.expectEqual(@as(usize, 3), pt.getLineCount());
}
test "PieceTable - insert" {
    var pt = try PieceTable.init(std.testing.allocator, 4096);
    defer pt.deinit();
    try pt.insert("Hello");
    try std.testing.expectEqual(@as(usize, 1), pt.pieces.items.len);
    try std.testing.expect(pt.modified);
}
test "PieceTable - insert newline" {
    var pt = try PieceTable.init(std.testing.allocator, 4096);
    defer pt.deinit();
    try pt.insert("Hello\n");
    try std.testing.expectEqual(@as(usize, 2), pt.line_count);
}
test "PieceTable - multiple inserts" {
    var pt = try PieceTable.init(std.testing.allocator, 4096);
    defer pt.deinit();
    try pt.insert("Hello ");
    try pt.insert("World");
    try std.testing.expectEqual(@as(usize, 2), pt.pieces.items.len);
    const content = try pt.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("Hello World", content);
}
test "PieceTable - getTotalLength" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Hello World");
    defer pt.deinit();
    try std.testing.expectEqual(@as(usize, 11), pt.getTotalLength());
}
test "PieceTable - document interface" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Hello\nWorld");
    defer pt.deinit();
    var doc = pt.document();
    try std.testing.expectEqual(@as(usize, 2), doc.getLineCount());
}
test "PieceTable - cursor operations" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Line 1\nLine 2");
    defer pt.deinit();
    var doc = pt.document();
    try std.testing.expectEqual(@as(usize, 1), doc.getCursorRow());
    try std.testing.expect(doc.moveCursorDown());
    try std.testing.expectEqual(@as(usize, 2), doc.getCursorRow());
    try std.testing.expect(doc.moveCursorUp());
    try std.testing.expectEqual(@as(usize, 1), doc.getCursorRow());
}
test "PieceTable - isModified" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Hello");
    defer pt.deinit();
    try std.testing.expect(!pt.isModified());
    try pt.insert("X");
    try std.testing.expect(pt.isModified());
    pt.clearModified();
    try std.testing.expect(!pt.isModified());
}
test "PieceTable - toSlice" {
    var pt = try PieceTable.initContent(std.testing.allocator, "Hello World");
    defer pt.deinit();
    const content = try pt.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("Hello World", content);
}
