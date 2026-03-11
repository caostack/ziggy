//! Terminal handling for raw mode and ANSI escape sequences
const std = @import("std");

pub const TerminalError = error{
    NotATTY,
    IoctlFailed,
    WriteFailed,
};

/// Terminal state before enabling raw mode
const OriginalTermios = struct {
    termios: std.os.linux.termios,
    is_valid: bool,
};

pub const Terminal = struct {
    original_state: OriginalTermios,
    stdout_handle: std.fs.File.Handle,
    write_buffer: [1024]u8,

    /// Enable raw mode (disable echo, canonical mode, signals)
    pub fn enableRawMode() !Terminal {
        const stdout = std.fs.File.stdout();

        // Check if TTY
        if (!stdout.isTty()) return TerminalError.NotATTY;

        // Get current termios
        var original_termios: std.os.linux.termios = undefined;
        const err = std.os.linux.tcgetattr(stdout.handle, &original_termios);
        if (std.posix.errno(err) != .SUCCESS) return TerminalError.IoctlFailed;

        // Create copy for modification
        var raw = original_termios;

        // Disable echo, canonical mode, signals
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;

        // Disable software flow control
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;

        // Disable output processing
        raw.oflag.OPOST = false;

        // Set 1 byte minimum read, no timeout
        // VMIN = 6, VTIME = 5 (standard termios indices)
        raw.cc[6] = 1;
        raw.cc[5] = 0;

        // Apply raw mode
        const err2 = std.os.linux.tcsetattr(stdout.handle, .NOW, &raw);
        if (std.posix.errno(err2) != .SUCCESS) return TerminalError.IoctlFailed;

        return .{
            .original_state = .{
                .termios = original_termios,
                .is_valid = true,
            },
            .stdout_handle = stdout.handle,
            .write_buffer = undefined,
        };
    }

    /// Restore original terminal settings
    pub fn disableRawMode(self: Terminal) void {
        if (!self.original_state.is_valid) return;

        _ = std.os.linux.tcsetattr(self.stdout_handle, .NOW, &self.original_state.termios);
    }

    /// Clear entire screen
    pub fn clearScreen(self: *const Terminal) !void {
        try self.writeAll("\x1b[2J");
    }

    /// Clear current line
    pub fn clearLine(self: *const Terminal) !void {
        try self.writeAll("\x1b[K");
    }

    /// Move cursor to (row, col) - 1-indexed
    pub fn moveCursor(self: *Terminal, row: usize, col: usize) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row, col });
        try self.writeAll(seq);
    }

    /// Hide cursor
    pub fn hideCursor(self: *Terminal) !void {
        try self.writeAll("\x1b[?25l");
    }

    /// Show cursor
    pub fn showCursor(self: *Terminal) !void {
        try self.writeAll("\x1b[?25h");
    }

    /// Get terminal window size
    pub fn getWindowSize(self: *Terminal) !struct { rows: usize, cols: usize } {
        var ws: std.posix.winsize = undefined;
        const err = std.os.linux.ioctl(
            self.stdout_handle,
            std.os.linux.T.IOCGWINSZ,
            @intFromPtr(&ws),
        );
        if (std.posix.errno(err) != .SUCCESS) return TerminalError.IoctlFailed;

        return .{
            .rows = ws.row,
            .cols = ws.col,
        };
    }

    /// Write string to stdout
    pub fn writeAll(self: *const Terminal, s: []const u8) !void {
        _ = self;
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(s);
    }

    /// Formatted write
    pub fn print(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        var buf: [256]u8 = undefined;
        const output = try std.fmt.bufPrint(&buf, fmt, args);
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(output);
    }
};

// ANSI color codes for syntax highlighting (future)
pub const Color = enum(u8) {
    reset = 0,
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,

    pub fn ansi(self: Color) []const u8 {
        const code = @intFromEnum(self);
        return "\x1b[" ++ std.fmt.comptimePrint("{d}m", .{code});
    }
};

test "terminal enable raw mode" {
    // This test requires a TTY, so we'll just test compilation
    // Actual testing will be done during manual integration testing
    const terminal = Terminal.enableRawMode() catch |err| {
        // Not a TTY in test environment, that's okay
        try std.testing.expect(err == TerminalError.NotATTY);
        return;
    };
    defer terminal.disableRawMode();

    // If we got here, we're in a TTY
    try terminal.moveCursor(1, 1);
    try terminal.clearScreen();
}

test "ansi color codes" {
    const red = Color.red;
    const reset = Color.reset;

    // Just verify the codes compile
    _ = red.ansi();
    _ = reset.ansi();
}
