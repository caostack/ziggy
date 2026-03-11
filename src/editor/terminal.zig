//! Terminal handling for raw mode and ANSI escape sequences
//! Supports both Windows and Linux platforms
const std = @import("std");
const builtin = @import("builtin");

const native_os = builtin.os.tag;
const windows = std.os.windows;
const linux = std.os.linux;

pub const TerminalError = error{
    NotATTY,
    IoctlFailed,
    WriteFailed,
    GetConsoleModeFailed,
    SetConsoleModeFailed,
};

/// Window size structure
pub const WindowSize = struct {
    rows: usize,
    cols: usize,
};

/// Platform-specific original terminal state
const OriginalState = union(enum) {
    linux: linux.termios,
    windows: struct {
        input_mode: u32,
        output_mode: u32,
    },
    none: void,
};

pub const Terminal = struct {
    original_state: OriginalState,
    stdout_handle: std.fs.File.Handle,
    stdin_handle: std.fs.File.Handle,
    is_valid: bool,

    /// Enable raw mode (disable echo, canonical mode, signals)
    pub fn enableRawMode() !Terminal {
        const stdout = std.fs.File.stdout();
        const stdin = std.fs.File.stdin();

        // Check if TTY
        if (!stdout.isTty()) return TerminalError.NotATTY;

        if (native_os == .windows) {
            return enableRawModeWindows(stdin, stdout);
        } else {
            return enableRawModeLinux(stdin, stdout);
        }
    }

    fn enableRawModeWindows(stdin: std.fs.File, stdout: std.fs.File) !Terminal {
        // Get current console modes
        var input_mode: u32 = undefined;
        var output_mode: u32 = undefined;

        if (windows.kernel32.GetConsoleMode(stdin.handle, &input_mode) == windows.FALSE) {
            return TerminalError.GetConsoleModeFailed;
        }
        if (windows.kernel32.GetConsoleMode(stdout.handle, &output_mode) == windows.FALSE) {
            return TerminalError.GetConsoleModeFailed;
        }

        // Save original state
        const original = OriginalState{ .windows = .{
            .input_mode = input_mode,
            .output_mode = output_mode,
        } };

        // Set raw input mode:
        // Disable ENABLE_LINE_INPUT (0x0002) - raw input
        // Disable ENABLE_ECHO_INPUT (0x0004) - no echo
        // Disable ENABLE_PROCESSED_INPUT (0x0001) - no Ctrl+C processing
        // Keep ENABLE_VIRTUAL_TERMINAL_INPUT (0x0200) for ANSI sequences
        const raw_input_mode: u32 = input_mode & ~(@as(u32, 0x0001 | 0x0002 | 0x0004));

        // Enable virtual terminal processing for output (ANSI escape sequences)
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
        const raw_output_mode: u32 = output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if (windows.kernel32.SetConsoleMode(stdin.handle, raw_input_mode) == windows.FALSE) {
            return TerminalError.SetConsoleModeFailed;
        }
        if (windows.kernel32.SetConsoleMode(stdout.handle, raw_output_mode) == windows.FALSE) {
            return TerminalError.SetConsoleModeFailed;
        }

        return .{
            .original_state = original,
            .stdout_handle = stdout.handle,
            .stdin_handle = stdin.handle,
            .is_valid = true,
        };
    }

    fn enableRawModeLinux(stdin: std.fs.File, stdout: std.fs.File) !Terminal {
        // Get current termios
        var original_termios: linux.termios = undefined;
        const fd: i32 = @intCast(stdout.handle);

        const err = linux.tcgetattr(fd, &original_termios);
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
        const err2 = linux.tcsetattr(fd, .NOW, &raw);
        if (std.posix.errno(err2) != .SUCCESS) return TerminalError.IoctlFailed;

        return .{
            .original_state = OriginalState{ .linux = original_termios },
            .stdout_handle = stdout.handle,
            .stdin_handle = stdin.handle,
            .is_valid = true,
        };
    }

    /// Restore original terminal settings
    pub fn disableRawMode(self: Terminal) void {
        if (!self.is_valid) return;

        if (native_os == .windows) {
            switch (self.original_state) {
                .windows => |state| {
                    _ = windows.kernel32.SetConsoleMode(self.stdin_handle, state.input_mode);
                    _ = windows.kernel32.SetConsoleMode(self.stdout_handle, state.output_mode);
                },
                else => {},
            }
        } else {
            switch (self.original_state) {
                .linux => |state| {
                    const fd: i32 = @intCast(self.stdout_handle);
                    _ = linux.tcsetattr(fd, .NOW, &state);
                },
                else => {},
            }
        }
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
    pub fn getWindowSize(self: *Terminal) TerminalError!WindowSize {
        if (native_os == .windows) {
            return self.getWindowSizeWindows();
        } else {
            return self.getWindowSizeLinux();
        }
    }

    fn getWindowSizeWindows(self: *Terminal) TerminalError!WindowSize {
        var info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (windows.kernel32.GetConsoleScreenBufferInfo(self.stdout_handle, &info) == windows.FALSE) {
            return TerminalError.IoctlFailed;
        }

        return .{
            .rows = @intCast(info.dwSize.Y),
            .cols = @intCast(info.dwSize.X),
        };
    }

    fn getWindowSizeLinux(self: *Terminal) TerminalError!WindowSize {
        var ws: std.posix.winsize = undefined;
        const fd: i32 = @intCast(self.stdout_handle);
        const err = linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&ws));
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
