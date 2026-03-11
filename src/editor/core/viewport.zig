//! Viewport - rendering state and scrolling logic
//! Manages what portion of the document is visible on screen

/// Viewport - tracks visible portion of document
pub const Viewport = struct {
    /// Screen dimensions
    rows: usize,
    cols: usize,

    /// Scroll offset (first visible line index)
    first_line: usize,

    /// Cursor screen position (1-indexed for terminal)
    cursor_screen_row: usize,
    cursor_screen_col: usize,

    const Self = @This();

    /// Initialize viewport with screen dimensions
    pub fn init(rows: usize, cols: usize) Self {
        return .{
            .rows = rows,
            .cols = cols,
            .first_line = 0,
            .cursor_screen_row = 1,
            .cursor_screen_col = 1,
        };
    }

    /// Get number of lines available for content (excluding status bar)
    pub fn contentLines(self: Self) usize {
        return if (self.rows > 1) self.rows - 1 else self.rows;
    }

    /// Get the last visible line index (exclusive)
    pub fn lastVisibleLine(self: Self) usize {
        return self.first_line + self.contentLines();
    }

    /// Check if a line is currently visible
    pub fn isLineVisible(self: Self, line: usize) bool {
        return line >= self.first_line and line < self.lastVisibleLine();
    }

    /// Scroll viewport to ensure a line is visible
    /// Returns true if scrolling occurred
    pub fn scrollToLine(self: *Self, line: usize) bool {
        const content = self.contentLines();

        if (line < self.first_line) {
            // Need to scroll up
            self.first_line = line;
            return true;
        } else if (line >= self.first_line + content) {
            // Need to scroll down
            if (content > 0) {
                self.first_line = line - content + 1;
            } else {
                self.first_line = line;
            }
            return true;
        }

        return false;
    }

    /// Scroll up by one screen (page up)
    pub fn pageUp(self: *Self) void {
        const content = self.contentLines();
        if (self.first_line >= content) {
            self.first_line -= content;
        } else {
            self.first_line = 0;
        }
    }

    /// Scroll down by one screen (page down)
    pub fn pageDown(self: *Self, total_lines: usize) void {
        const content = self.contentLines();
        const max_first = if (total_lines > content) total_lines - content else 0;
        self.first_line = @min(self.first_line + content, max_first);
    }

    /// Scroll up by one line
    pub fn scrollUp(self: *Self) bool {
        if (self.first_line == 0) return false;
        self.first_line -= 1;
        return true;
    }

    /// Scroll down by one line
    pub fn scrollDown(self: *Self, total_lines: usize) bool {
        const content = self.contentLines();
        if (self.first_line + content >= total_lines) return false;
        self.first_line += 1;
        return true;
    }

    /// Update cursor screen position based on buffer cursor
    /// Returns true if scrolling occurred
    pub fn updateCursor(self: *Self, buffer_line: usize, buffer_col: usize) bool {
        const scrolled = self.scrollToLine(buffer_line);

        // Calculate screen position (1-indexed)
        self.cursor_screen_row = buffer_line - self.first_line + 1;
        self.cursor_screen_col = buffer_col + 1;

        // Clamp cursor column to screen width
        if (self.cursor_screen_col > self.cols) {
            self.cursor_screen_col = self.cols;
        }

        return scrolled;
    }

    /// Convert buffer line to screen line
    pub fn bufferToScreenLine(self: Self, buffer_line: usize) ?usize {
        if (!self.isLineVisible(buffer_line)) return null;
        return buffer_line - self.first_line + 1; // 1-indexed
    }

    /// Convert screen line to buffer line
    pub fn screenToBufferLine(self: Self, screen_line: usize) ?usize {
        if (screen_line == 0 or screen_line > self.contentLines()) return null;
        return self.first_line + screen_line - 1;
    }

    /// Get scroll percentage (0.0 to 1.0)
    pub fn scrollPercent(self: Self, total_lines: usize) f32 {
        if (total_lines <= self.contentLines()) return 0.0;
        const max_scroll = total_lines - self.contentLines();
        return @as(f32, @floatFromInt(self.first_line)) / @as(f32, @floatFromInt(max_scroll));
    }

    /// Resize viewport
    pub fn resize(self: *Self, new_rows: usize, new_cols: usize) void {
        self.rows = new_rows;
        self.cols = new_cols;
    }

    /// Reset to initial state
    pub fn reset(self: *Self) void {
        self.first_line = 0;
        self.cursor_screen_row = 1;
        self.cursor_screen_col = 1;
    }

    /// Check if at top of document
    pub fn atTop(self: Self) bool {
        return self.first_line == 0;
    }

    /// Check if at bottom of document
    pub fn atBottom(self: Self, total_lines: usize) bool {
        return self.first_line + self.contentLines() >= total_lines;
    }

    /// Get visible line range (start, end exclusive)
    pub fn getVisibleRange(self: Self, total_lines: usize) struct { start: usize, end: usize } {
        return .{
            .start = self.first_line,
            .end = @min(self.first_line + self.contentLines(), total_lines),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "Viewport - init" {
    const vp = Viewport.init(24, 80);

    try testing.expectEqual(@as(usize, 24), vp.rows);
    try testing.expectEqual(@as(usize, 80), vp.cols);
    try testing.expectEqual(@as(usize, 0), vp.first_line);
    try testing.expectEqual(@as(usize, 1), vp.cursor_screen_row);
    try testing.expectEqual(@as(usize, 1), vp.cursor_screen_col);
}

test "Viewport - contentLines" {
    const vp1 = Viewport.init(24, 80);
    try testing.expectEqual(@as(usize, 23), vp1.contentLines());

    const vp2 = Viewport.init(1, 80);
    try testing.expectEqual(@as(usize, 1), vp2.contentLines());

    const vp3 = Viewport.init(0, 80);
    try testing.expectEqual(@as(usize, 0), vp3.contentLines());
}

test "Viewport - isLineVisible" {
    var vp = Viewport.init(24, 80); // 23 content lines

    try testing.expect(vp.isLineVisible(0));
    try testing.expect(vp.isLineVisible(22));
    try testing.expect(!vp.isLineVisible(23));
    try testing.expect(!vp.isLineVisible(100));

    vp.first_line = 10;
    try testing.expect(!vp.isLineVisible(9));
    try testing.expect(vp.isLineVisible(10));
    try testing.expect(vp.isLineVisible(32));
    try testing.expect(!vp.isLineVisible(33));
}

test "Viewport - scrollToLine up" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 10;

    const scrolled = vp.scrollToLine(5);
    try testing.expect(scrolled);
    try testing.expectEqual(@as(usize, 5), vp.first_line);
}

test "Viewport - scrollToLine down" {
    var vp = Viewport.init(24, 80);

    const scrolled = vp.scrollToLine(30);
    try testing.expect(scrolled);
    // 30 - 23 + 1 = 8
    try testing.expectEqual(@as(usize, 8), vp.first_line);
}

test "Viewport - scrollToLine no scroll needed" {
    var vp = Viewport.init(24, 80);

    const scrolled = vp.scrollToLine(10);
    try testing.expect(!scrolled);
    try testing.expectEqual(@as(usize, 0), vp.first_line);
}

test "Viewport - pageUp" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 50;

    vp.pageUp();
    try testing.expectEqual(@as(usize, 27), vp.first_line); // 50 - 23

    vp.pageUp();
    try testing.expectEqual(@as(usize, 4), vp.first_line);

    vp.pageUp();
    try testing.expectEqual(@as(usize, 0), vp.first_line); // Clamped
}

test "Viewport - pageDown" {
    var vp = Viewport.init(24, 80);
    const total_lines = 100;

    vp.pageDown(total_lines);
    try testing.expectEqual(@as(usize, 23), vp.first_line);

    vp.pageDown(total_lines);
    try testing.expectEqual(@as(usize, 46), vp.first_line);

    // Scroll to near end
    vp.first_line = 70;
    vp.pageDown(total_lines);
    try testing.expectEqual(@as(usize, 77), vp.first_line); // 100 - 23 = 77 max
}

test "Viewport - scrollUp/Down" {
    var vp = Viewport.init(24, 80);
    const total_lines = 100;

    // Can't scroll up at top
    try testing.expect(!vp.scrollUp());

    // Scroll down
    try testing.expect(vp.scrollDown(total_lines));
    try testing.expectEqual(@as(usize, 1), vp.first_line);

    // Now can scroll up
    try testing.expect(vp.scrollUp());
    try testing.expectEqual(@as(usize, 0), vp.first_line);
}

test "Viewport - updateCursor" {
    var vp = Viewport.init(24, 80);

    const scrolled1 = vp.updateCursor(5, 10);
    try testing.expect(!scrolled1); // No scroll needed
    try testing.expectEqual(@as(usize, 6), vp.cursor_screen_row); // 5 - 0 + 1
    try testing.expectEqual(@as(usize, 11), vp.cursor_screen_col); // 10 + 1

    // Cursor at line that requires scroll
    const scrolled2 = vp.updateCursor(30, 5);
    try testing.expect(scrolled2);
    try testing.expectEqual(@as(usize, 8), vp.first_line); // 30 - 23 + 1
    try testing.expectEqual(@as(usize, 23), vp.cursor_screen_row); // 30 - 8 + 1
}

test "Viewport - buffer/screen line conversion" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 10;

    // Buffer to screen
    try testing.expectEqual(@as(usize, 1), vp.bufferToScreenLine(10));
    try testing.expectEqual(@as(usize, 23), vp.bufferToScreenLine(32));
    try testing.expectEqual(@as(?usize, null), vp.bufferToScreenLine(9));
    try testing.expectEqual(@as(?usize, null), vp.bufferToScreenLine(33));

    // Screen to buffer
    try testing.expectEqual(@as(usize, 10), vp.screenToBufferLine(1));
    try testing.expectEqual(@as(usize, 32), vp.screenToBufferLine(23));
    try testing.expectEqual(@as(?usize, null), vp.screenToBufferLine(0));
    try testing.expectEqual(@as(?usize, null), vp.screenToBufferLine(24));
}

test "Viewport - scrollPercent" {
    var vp = Viewport.init(24, 80);
    const total_lines = 100;

    try testing.expectEqual(@as(f32, 0.0), vp.scrollPercent(total_lines));

    vp.first_line = 38; // 50% of (100 - 23)
    try testing.expectEqual(@as(f32, 0.5), vp.scrollPercent(total_lines));

    vp.first_line = 77; // 100%
    try testing.expectEqual(@as(f32, 1.0), vp.scrollPercent(total_lines));

    // More content than viewport
    try testing.expectEqual(@as(f32, 0.0), vp.scrollPercent(10));
}

test "Viewport - atTop/atBottom" {
    var vp = Viewport.init(24, 80);
    const total_lines = 100;

    try testing.expect(vp.atTop());
    try testing.expect(!vp.atBottom(total_lines));

    vp.first_line = 77;
    try testing.expect(!vp.atTop());
    try testing.expect(vp.atBottom(total_lines));
}

test "Viewport - getVisibleRange" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 10;

    const range = vp.getVisibleRange(100);
    try testing.expectEqual(@as(usize, 10), range.start);
    try testing.expectEqual(@as(usize, 33), range.end);

    // Near end
    vp.first_line = 90;
    const range2 = vp.getVisibleRange(95);
    try testing.expectEqual(@as(usize, 90), range2.start);
    try testing.expectEqual(@as(usize, 95), range2.end); // Clamped to total
}

test "Viewport - resize" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 10;

    vp.resize(40, 120);
    try testing.expectEqual(@as(usize, 40), vp.rows);
    try testing.expectEqual(@as(usize, 120), vp.cols);
    try testing.expectEqual(@as(usize, 10), vp.first_line); // Preserved
}

test "Viewport - cursor col clamp" {
    var vp = Viewport.init(24, 80);

    _ = vp.updateCursor(0, 100); // col > screen width
    try testing.expectEqual(@as(usize, 80), vp.cursor_screen_col); // Clamped
}

test "Viewport - reset" {
    var vp = Viewport.init(24, 80);
    vp.first_line = 50;
    vp.cursor_screen_row = 10;
    vp.cursor_screen_col = 20;

    vp.reset();
    try testing.expectEqual(@as(usize, 0), vp.first_line);
    try testing.expectEqual(@as(usize, 1), vp.cursor_screen_row);
    try testing.expectEqual(@as(usize, 1), vp.cursor_screen_col);
}
