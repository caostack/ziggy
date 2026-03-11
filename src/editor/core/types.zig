//! Core type definitions shared across the editor
const std = @import("std");

/// Position in the document (byte offset)
pub const Position = struct {
    row: usize,
    col: usize,

    pub fn init(row: usize, col: usize) Position {
        return .{ .row = row, .col = col };
    }

    pub fn eql(self: Position, other: Position) bool {
        return self.row == other.row and self.col == other.col;
    }

    pub fn lessThan(self: Position, other: Position) bool {
        if (self.row != other.row) return self.row < other.row;
        return self.col < other.col;
    }
};

/// Range in the document
pub const Range = struct {
    start: Position,
    end: Position,

    pub fn init(start: Position, end: Position) Range {
        return .{ .start = start, .end = end };
    }

    pub fn isEmpty(self: Range) bool {
        return self.start.eql(self.end);
    }

    pub fn contains(self: Range, pos: Position) bool {
        return !pos.lessThan(self.start) and pos.lessThan(self.end);
    }

    pub fn length(self: Range) usize {
        if (self.start.row == self.end.row) {
            return self.end.col - self.start.col;
        }
        // Multi-line range - just return 0 for now
        return 0;
    }
};

/// Editor-wide errors
pub const EditorError = error{
    OutOfMemory,
    InvalidUtf8,
    InvalidPosition,
    LineNotFound,
    FileNotFound,
    FileSaveFailed,
    TerminalError,
    NotATTY,
    Quit,
    SaveFailed,
    OpenFailed,
};

test "Position equality" {
    const p1 = Position.init(1, 5);
    const p2 = Position.init(1, 5);
    const p3 = Position.init(2, 0);

    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}

test "Position comparison" {
    const p1 = Position.init(1, 5);
    const p2 = Position.init(1, 10);
    const p3 = Position.init(2, 0);

    try std.testing.expect(p1.lessThan(p2));
    try std.testing.expect(p2.lessThan(p3));
    try std.testing.expect(!p3.lessThan(p1));
}

test "Range isEmpty" {
    const r1 = Range.init(Position.init(1, 5), Position.init(1, 5));
    const r2 = Range.init(Position.init(1, 5), Position.init(1, 10));

    try std.testing.expect(r1.isEmpty());
    try std.testing.expect(!r2.isEmpty());
}

test "Range contains" {
    const r = Range.init(Position.init(1, 5), Position.init(1, 10));

    try std.testing.expect(r.contains(Position.init(1, 7)));
    try std.testing.expect(!r.contains(Position.init(1, 3)));
    try std.testing.expect(!r.contains(Position.init(1, 10)));
}

test "Range length - same line" {
    const r = Range.init(Position.init(1, 5), Position.init(1, 10));
    try std.testing.expectEqual(@as(usize, 5), r.length());
}

test "Range length - multi-line returns 0" {
    const r = Range.init(Position.init(1, 5), Position.init(2, 3));
    try std.testing.expectEqual(@as(usize, 0), r.length());
}

test "Position init" {
    const p = Position.init(10, 20);
    try std.testing.expectEqual(@as(usize, 10), p.row);
    try std.testing.expectEqual(@as(usize, 20), p.col);
}
