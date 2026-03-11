//! Selection model - cursor and range selection
//! A cursor is just a selection where anchor == cursor
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Selection - represents a cursor or a range
/// When anchor == cursor, it's a cursor (no selection)
/// When anchor != cursor, it's a range selection
pub const Selection = struct {
    anchor: usize, // Selection start point (doesn't move when extending)
    cursor: usize, // Current cursor position (moves when extending)

    const Self = @This();

    /// Create a cursor-only selection at a position
    pub fn cursorOnly(pos: usize) Self {
        return .{ .anchor = pos, .cursor = pos };
    }

    /// Create a range selection from start to end
    pub fn range(range_start: usize, range_end: usize) Self {
        return .{ .anchor = range_start, .cursor = range_end };
    }

    /// Check if selection is empty (just a cursor)
    pub fn isEmpty(self: Self) bool {
        return self.anchor == self.cursor;
    }

    /// Check if selection has content (range selection)
    pub fn hasSelection(self: Self) bool {
        return self.anchor != self.cursor;
    }

    /// Get the start of the selection (min of anchor and cursor)
    pub fn getStart(self: Self) usize {
        return @min(self.anchor, self.cursor);
    }

    /// Get the end of the selection (max of anchor and cursor)
    pub fn getEnd(self: Self) usize {
        return @max(self.anchor, self.cursor);
    }

    /// Get selection length
    pub fn length(self: Self) usize {
        return self.getEnd() - self.getStart();
    }

    /// Move cursor to new position (deselects)
    pub fn moveTo(self: *Self, new_pos: usize) void {
        self.cursor = new_pos;
        self.anchor = new_pos;
    }

    /// Move cursor without changing anchor (extends selection)
    pub fn extendTo(self: *Self, new_pos: usize) void {
        self.cursor = new_pos;
    }

    /// Move cursor by delta
    pub fn moveBy(self: *Self, delta: isize) void {
        if (delta < 0) {
            const abs_delta = @as(usize, @intCast(-delta));
            if (self.cursor >= abs_delta) {
                self.cursor -= abs_delta;
            } else {
                self.cursor = 0;
            }
        } else {
            self.cursor += @as(usize, @intCast(delta));
        }
        self.anchor = self.cursor;
    }

    /// Collapse selection to start
    pub fn collapseToStart(self: *Self) void {
        self.cursor = self.getStart();
        self.anchor = self.cursor;
    }

    /// Collapse selection to end
    pub fn collapseToEnd(self: *Self) void {
        self.anchor = self.getEnd();
        self.cursor = self.anchor;
    }

    /// Collapse selection to cursor position
    pub fn collapse(self: *Self) void {
        self.anchor = self.cursor;
    }

    /// Check if position is within selection
    pub fn contains(self: Self, pos: usize) bool {
        return pos >= self.getStart() and pos < self.getEnd();
    }

    /// Direction of selection (1 if cursor >= anchor, -1 otherwise)
    pub fn direction(self: Self) isize {
        return if (self.cursor >= self.anchor) 1 else -1;
    }

    /// Create a copy
    pub fn clone(self: Self) Self {
        return .{ .anchor = self.anchor, .cursor = self.cursor };
    }
};

/// SelectionManager - manages primary and optional multiple selections
pub const SelectionManager = struct {
    primary: Selection,
    secondary: ?ArrayList(Selection),
    allocator: Allocator,

    const Self = @This();

    /// Initialize with a cursor at position 0
    pub fn init(allocator: Allocator) Self {
        return .{
            .primary = Selection.cursorOnly(0),
            .secondary = null,
            .allocator = allocator,
        };
    }

    /// Initialize with cursor at specific position
    pub fn initAt(allocator: Allocator, pos: usize) Self {
        return .{
            .primary = Selection.cursorOnly(pos),
            .secondary = null,
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.secondary) |*list| {
            list.deinit(self.allocator);
        }
    }

    /// Get primary selection
    pub fn getPrimary(self: Self) Selection {
        return self.primary;
    }

    /// Get cursor position
    pub fn getCursor(self: Self) usize {
        return self.primary.cursor;
    }

    /// Get anchor position
    pub fn getAnchor(self: Self) usize {
        return self.primary.anchor;
    }

    /// Move primary cursor to position
    pub fn moveTo(self: *Self, pos: usize) void {
        self.primary.moveTo(pos);
    }

    /// Move primary cursor by delta
    pub fn moveBy(self: *Self, delta: isize) void {
        self.primary.moveBy(delta);
    }

    /// Extend primary selection
    pub fn extendTo(self: *Self, pos: usize) void {
        self.primary.extendTo(pos);
    }

    /// Collapse primary selection
    pub fn collapse(self: *Self) void {
        self.primary.collapse();
    }

    /// Check if there's an active selection
    pub fn hasSelection(self: Self) bool {
        return self.primary.hasSelection();
    }

    /// Get selection range
    pub fn getRange(self: Self) struct { start: usize, end: usize } {
        return .{
            .start = self.primary.getStart(),
            .end = self.primary.getEnd(),
        };
    }

    /// Get selection length
    pub fn getSelectionLength(self: Self) usize {
        return self.primary.length();
    }

    // Multi-cursor support (future)

    /// Check if multiple cursors exist
    pub fn hasMultipleCursors(self: Self) bool {
        if (self.secondary) |list| {
            return list.items.len > 0;
        }
        return false;
    }

    /// Get total cursor count
    pub fn cursorCount(self: Self) usize {
        if (self.secondary) |list| {
            return 1 + list.items.len;
        }
        return 1;
    }

    /// Add a secondary cursor (for multi-cursor editing)
    pub fn addCursor(self: *Self, pos: usize) !void {
        if (self.secondary == null) {
            self.secondary = ArrayList(Selection).init(self.allocator);
        }
        try self.secondary.?.append(Selection.cursorOnly(pos));
    }

    /// Clear all secondary cursors
    pub fn clearSecondaryCursors(self: *Self) void {
        if (self.secondary) |*list| {
            list.clearRetainingCapacity();
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Selection - cursorOnly creation" {
    const sel = Selection.cursorOnly(10);

    try std.testing.expect(sel.isEmpty());
    try std.testing.expect(!sel.hasSelection());
    try std.testing.expectEqual(@as(usize, 10), sel.cursor);
    try std.testing.expectEqual(@as(usize, 10), sel.anchor);
}

test "Selection - range creation" {
    const sel = Selection.range(5, 15);

    try std.testing.expect(!sel.isEmpty());
    try std.testing.expect(sel.hasSelection());
    try std.testing.expectEqual(@as(usize, 5), sel.anchor);
    try std.testing.expectEqual(@as(usize, 15), sel.cursor);
    try std.testing.expectEqual(@as(usize, 5), sel.getStart());
    try std.testing.expectEqual(@as(usize, 15), sel.getEnd());
    try std.testing.expectEqual(@as(usize, 10), sel.length());
}

test "Selection - reversed range" {
    const sel = Selection.range(15, 5);

    try std.testing.expect(sel.hasSelection());
    try std.testing.expectEqual(@as(usize, 5), sel.getStart());
    try std.testing.expectEqual(@as(usize, 15), sel.getEnd());
    try std.testing.expectEqual(@as(usize, 10), sel.length());
}

test "Selection - moveTo" {
    var sel = Selection.range(5, 15);
    sel.moveTo(20);

    try std.testing.expect(sel.isEmpty());
    try std.testing.expectEqual(@as(usize, 20), sel.cursor);
    try std.testing.expectEqual(@as(usize, 20), sel.anchor);
}

test "Selection - extendTo" {
    var sel = Selection.cursorOnly(10);
    sel.extendTo(20);

    try std.testing.expect(sel.hasSelection());
    try std.testing.expectEqual(@as(usize, 10), sel.anchor);
    try std.testing.expectEqual(@as(usize, 20), sel.cursor);
}

test "Selection - moveBy positive" {
    var sel = Selection.cursorOnly(10);
    sel.moveBy(5);

    try std.testing.expectEqual(@as(usize, 15), sel.cursor);
    try std.testing.expectEqual(@as(usize, 15), sel.anchor);
}

test "Selection - moveBy negative" {
    var sel = Selection.cursorOnly(10);
    sel.moveBy(-3);

    try std.testing.expectEqual(@as(usize, 7), sel.cursor);
    try std.testing.expectEqual(@as(usize, 7), sel.anchor);
}

test "Selection - moveBy negative clamped to zero" {
    var sel = Selection.cursorOnly(2);
    sel.moveBy(-10);

    try std.testing.expectEqual(@as(usize, 0), sel.cursor);
}

test "Selection - collapseToStart" {
    var sel = Selection.range(5, 15);
    sel.collapseToStart();

    try std.testing.expect(sel.isEmpty());
    try std.testing.expectEqual(@as(usize, 5), sel.cursor);
}

test "Selection - collapseToEnd" {
    var sel = Selection.range(5, 15);
    sel.collapseToEnd();

    try std.testing.expect(sel.isEmpty());
    try std.testing.expectEqual(@as(usize, 15), sel.cursor);
}

test "Selection - contains" {
    const sel = Selection.range(5, 15);

    try std.testing.expect(!sel.contains(4));
    try std.testing.expect(sel.contains(5));
    try std.testing.expect(sel.contains(10));
    try std.testing.expect(!sel.contains(15));
    try std.testing.expect(!sel.contains(20));
}

test "Selection - direction" {
    const forward = Selection.range(5, 15);
    const backward = Selection.range(15, 5);
    const cursor = Selection.cursorOnly(10);

    try std.testing.expectEqual(@as(isize, 1), forward.direction());
    try std.testing.expectEqual(@as(isize, -1), backward.direction());
    try std.testing.expectEqual(@as(isize, 1), cursor.direction());
}

test "Selection - clone" {
    const original = Selection.range(5, 15);
    const copy = original.clone();

    try std.testing.expectEqual(original.anchor, copy.anchor);
    try std.testing.expectEqual(original.cursor, copy.cursor);
}

test "SelectionManager - init" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(mgr.getCursor() == 0);
    try std.testing.expect(!mgr.hasSelection());
}

test "SelectionManager - initAt" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.initAt(allocator, 100);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 100), mgr.getCursor());
}

test "SelectionManager - moveTo" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.init(allocator);
    defer mgr.deinit();

    mgr.moveTo(50);
    try std.testing.expectEqual(@as(usize, 50), mgr.getCursor());
}

test "SelectionManager - extendTo creates selection" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.initAt(allocator, 10);
    defer mgr.deinit();

    mgr.extendTo(20);
    try std.testing.expect(mgr.hasSelection());
    try std.testing.expectEqual(@as(usize, 10), mgr.getRange().start);
    try std.testing.expectEqual(@as(usize, 20), mgr.getRange().end);
}

test "SelectionManager - collapse" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.initAt(allocator, 10);
    defer mgr.deinit();

    mgr.extendTo(20);
    try std.testing.expect(mgr.hasSelection());

    mgr.collapse();
    try std.testing.expect(!mgr.hasSelection());
}

test "SelectionManager - multi-cursor" {
    const allocator = std.testing.allocator;
    var mgr = SelectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(!mgr.hasMultipleCursors());
    try std.testing.expectEqual(@as(usize, 1), mgr.cursorCount());

    try mgr.addCursor(10);
    try mgr.addCursor(20);

    try std.testing.expect(mgr.hasMultipleCursors());
    try std.testing.expectEqual(@as(usize, 3), mgr.cursorCount());

    mgr.clearSecondaryCursors();
    try std.testing.expect(!mgr.hasMultipleCursors());
    try std.testing.expectEqual(@as(usize, 1), mgr.cursorCount());
}
