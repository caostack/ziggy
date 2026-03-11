//! Screen rendering and cursor positioning
const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Buffer = @import("buffer.zig").Buffer;

pub const Screen = struct {
    terminal: *Terminal,
    window_rows: usize,
    window_cols: usize,
    screen_rows: usize,
    screen_cols: usize,

    /// Offset for scrolling (first visible line)
    row_offset: usize = 0,

    pub fn init(terminal: *Terminal) !Screen {
        const size = try terminal.getWindowSize();

        // Reserve bottom row for status bar
        return .{
            .terminal = terminal,
            .window_rows = size.rows,
            .window_cols = size.cols,
            .screen_rows = if (size.rows > 0) size.rows - 1 else 0, // Reserve status line
            .screen_cols = size.cols,
        };
    }

    /// Refresh screen with current buffer content
    pub fn refresh(self: *Screen, buffer: *const Buffer, filename: ?[]const u8, modified: bool) !void {
        // Hide cursor during redraw
        try self.terminal.hideCursor();
        defer {
            self.terminal.showCursor() catch {};
        }

        // Move to top-left
        try self.terminal.moveCursor(1, 1);

        // Draw visible portion of buffer
        try self.drawBuffer(buffer);

        // Draw status bar
        try self.drawStatusBar(filename, modified, buffer);

        // Position cursor at current position
        try self.positionCursor(buffer);
    }

    fn drawBuffer(self: *Screen, buffer: *const Buffer) !void {
        const line_count = buffer.getLineCount();
        const start_line = @min(self.row_offset, line_count);
        const end_line = @min(start_line + self.screen_rows, line_count);

        for (start_line..end_line) |line_idx| {
            const line = buffer.getLine(line_idx) orelse continue;

            // Truncate to screen width
            const display_len = @min(line.len, self.screen_cols);

            // Write line content
            try self.terminal.writeAll(line[0..display_len]);

            // Clear to end of line
            try self.terminal.clearLine();

            // Move to next line (use CRLF for proper terminal handling)
            try self.terminal.writeAll("\r\n");
        }

        // Clear remaining lines
        const lines_drawn = end_line - start_line;
        if (lines_drawn < self.screen_rows) {
            const remaining = self.screen_rows - lines_drawn;
            for (0..remaining) |_| {
                try self.terminal.clearLine();
                try self.terminal.writeAll("\r\n");
            }
        }
    }

    fn drawStatusBar(self: *Screen, filename: ?[]const u8, modified: bool, buffer: *const Buffer) !void {
        // Move to status line (bottom row)
        const status_row = if (self.window_rows > 0) self.window_rows else 1;
        try self.terminal.moveCursor(status_row, 1);

        // Invert colors for status bar
        try self.terminal.writeAll("\x1b[7m");

        // Build status string
        const name = filename orelse "[No Name]";
        const mod_flag = if (modified) " (+)" else "";
        const line_count = buffer.getLineCount();

        // Calculate max filename length
        const status_format = " {s}{s} | {d} lines ";
        const format_len = status_format.len - 6; // Subtract format placeholders
        const max_name_len = if (self.screen_cols > format_len + 20)
            self.screen_cols - format_len - 20
        else
            20;

        // Truncate filename if needed
        const display_name = blk: {
            if (name.len > max_name_len) {
                break :blk name[name.len - max_name_len + 3 ..];
            }
            break :blk name;
        };

        try self.terminal.print(status_format, .{ display_name, mod_flag, line_count });

        // Reset colors
        try self.terminal.writeAll("\x1b[m");
    }

    fn positionCursor(self: *Screen, buffer: *const Buffer) !void {
        // Calculate screen position from buffer cursor
        const cursor_row = buffer.cursor_row - self.row_offset + 1;
        const cursor_col = buffer.cursor_col + 1;

        try self.terminal.moveCursor(cursor_row, cursor_col);
    }

    /// Scroll screen if cursor moved out of view
    pub fn scrollIfNeeded(self: *Screen, buffer: *const Buffer) void {
        if (buffer.cursor_row < self.row_offset) {
            self.row_offset = buffer.cursor_row;
        } else if (buffer.cursor_row >= self.row_offset + self.screen_rows) {
            self.row_offset = buffer.cursor_row - self.screen_rows + 1;
        }
    }
};

test "screen init" {
    // This test requires a terminal, so we'll just test compilation
    // Actual testing will be done during manual integration testing
    const terminal = Terminal.enableRawMode() catch |err| {
        // Not a TTY in test environment, that's okay
        _ = err;
        return;
    };
    defer terminal.disableRawMode();

    const screen = try Screen.init(@constCast(&terminal));
    _ = screen;
}
