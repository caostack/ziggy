//! Terminal adapter - abstract interface for terminal operations
//! Supports cross-platform raw mode and ANSI sequences
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const TerminalError = types.TerminalError;
const WindowSize = types.WindowSize;

const native_os = builtin.os.tag;
const windows = std.os.windows;
const linux = std.os.linux;

/// Terminal VTable - adapter implementations must provide these functions
pub const TerminalVTable = struct {
    /// Clean up and restore original state
    deinit: *const fn (*anyopaque) void,

    /// Clear entire screen
    clearScreen: *const fn (*anyopaque) TerminalError!void,

    /// Clear current line
    clearLine: *const fn (*anyopaque) TerminalError!void,

    /// Move cursor to (row, col) - 1-indexed
    moveCursor: *const fn (*anyopaque, usize, usize) TerminalError!void,

    /// Hide cursor
    hideCursor: *const fn (*anyopaque) TerminalError!void,

    /// Show cursor
    showCursor: *const fn (*anyopaque) TerminalError!void,

    /// Get terminal window size
    getWindowSize: *const fn (*anyopaque) TerminalError!WindowSize,

    /// Write string to terminal
    writeAll: *const fn (*anyopaque, []const u8) TerminalError!void,

    /// Formatted write
    print: *const fn (*anyopaque, []const u8, anytype) TerminalError!void,
};

/// Terminal interface - wraps any terminal adapter implementation
pub const Terminal = struct {
    ptr: *anyopaque,
    vtable: *const TerminalVTable,

    const Self = @This();

    /// Create Terminal wrapper from any implementation
    pub fn init(ptr: anytype, vtable: *const TerminalVTable) Self {
        return .{
            .ptr = @ptrCast(@alignCast(ptr)),
            .vtable = vtable,
        };
    }

    /// Clean up resources
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }

    /// Clear screen
    pub fn clearScreen(self: Self) TerminalError!void {
        return self.vtable.clearScreen(self.ptr);
    }

    /// Clear line
    pub fn clearLine(self: Self) TerminalError!void {
        return self.vtable.clearLine(self.ptr);
    }

    /// Move cursor
    pub fn moveCursor(self: *Self, row: usize, col: usize) TerminalError!void {
        return self.vtable.moveCursor(self.ptr, row, col);
    }

    /// Hide cursor
    pub fn hideCursor(self: *Self) TerminalError!void {
        return self.vtable.hideCursor(self.ptr);
    }

    /// Show cursor
    pub fn showCursor(self: *Self) TerminalError!void {
        return self.vtable.showCursor(self.ptr);
    }

    /// Get window size
    pub fn getWindowSize(self: *Self) TerminalError!WindowSize {
        return self.vtable.getWindowSize(self.ptr);
    }

    /// Write string
    pub fn writeAll(self: Self, s: []const u8) TerminalError!void {
        return self.vtable.writeAll(self.ptr, s);
    }

    /// Formatted print
    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) TerminalError!void {
        return self.vtable.print(self.ptr, fmt, args);
    }
};

/// NativeTerminal - real terminal implementation
pub const NativeTerminal = struct {
    original_state: OriginalState,
    stdout_handle: std.fs.File.Handle,
    stdin_handle: std.fs.File.Handle,
    is_valid: bool,

    /// Platform-specific original terminal state
    const OriginalState = union(enum) {
        linux: linux.termios,
        windows: struct {
            input_mode: u32,
            output_mode: u32,
        },
        none: void,
    };

    const Self = @This();

    /// Enable raw mode and return NativeTerminal
    pub fn enableRawMode() !Self {
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

    fn enableRawModeWindows(stdin: std.fs.File, stdout: std.fs.File) !Self {
        var input_mode: u32 = undefined;
        var output_mode: u32 = undefined;

        if (windows.kernel32.GetConsoleMode(stdin.handle, &input_mode) == windows.FALSE) {
            return TerminalError.GetConsoleModeFailed;
        }
        if (windows.kernel32.GetConsoleMode(stdout.handle, &output_mode) == windows.FALSE) {
            return TerminalError.GetConsoleModeFailed;
        }

        const original = OriginalState{ .windows = .{
            .input_mode = input_mode,
            .output_mode = output_mode,
        } };

        // Set raw input mode
        const raw_input_mode: u32 = input_mode & ~(@as(u32, 0x0001 | 0x0002 | 0x0004));

        // Enable virtual terminal processing for output
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

    fn enableRawModeLinux(stdin: std.fs.File, stdout: std.fs.File) !Self {
        var original_termios: linux.termios = undefined;
        const fd: i32 = @intCast(stdout.handle);

        const err = linux.tcgetattr(fd, &original_termios);
        if (std.posix.errno(err) != .SUCCESS) return TerminalError.IoctlFailed;

        var raw = original_termios;

        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;

        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;

        raw.oflag.OPOST = false;

        raw.cc[6] = 1;
        raw.cc[5] = 0;

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
    pub fn disableRawMode(self: Self) void {
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

    // Terminal operations
    pub fn clearScreen(self: *const Self) TerminalError!void {
        _ = self;
        try writeAllNative("\x1b[2J");
    }

    pub fn clearLine(self: *const Self) TerminalError!void {
        _ = self;
        try writeAllNative("\x1b[K");
    }

    pub fn moveCursor(self: *Self, row: usize, col: usize) TerminalError!void {
        _ = self;
        var buf: [32]u8 = undefined;
        const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row, col }) catch return TerminalError.WriteFailed;
        try writeAllNative(seq);
    }

    pub fn hideCursor(self: *Self) TerminalError!void {
        _ = self;
        try writeAllNative("\x1b[?25l");
    }

    pub fn showCursor(self: *Self) TerminalError!void {
        _ = self;
        try writeAllNative("\x1b[?25h");
    }

    pub fn getWindowSize(self: *Self) TerminalError!WindowSize {
        _ = self;
        if (native_os == .windows) {
            return getWindowSizeWindows();
        } else {
            return getWindowSizeLinux();
        }
    }

    fn getWindowSizeWindows() TerminalError!WindowSize {
        const stdout = std.fs.File.stdout();
        var info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (windows.kernel32.GetConsoleScreenBufferInfo(stdout.handle, &info) == windows.FALSE) {
            return TerminalError.IoctlFailed;
        }

        return .{
            .rows = @intCast(info.dwSize.Y),
            .cols = @intCast(info.dwSize.X),
        };
    }

    fn getWindowSizeLinux() TerminalError!WindowSize {
        var ws: std.posix.winsize = undefined;
        const stdout = std.fs.File.stdout();
        const fd: i32 = @intCast(stdout.handle);
        const err = linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&ws));
        if (std.posix.errno(err) != .SUCCESS) return TerminalError.IoctlFailed;

        return .{
            .rows = ws.row,
            .cols = ws.col,
        };
    }

    pub fn writeAll(self: *const Self, s: []const u8) TerminalError!void {
        _ = self;
        try writeAllNative(s);
    }

    fn writeAllNative(s: []const u8) TerminalError!void {
        const stdout = std.fs.File.stdout();
        stdout.writeAll(s) catch return TerminalError.WriteFailed;
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) TerminalError!void {
        _ = self;
        var buf: [256]u8 = undefined;
        const output = std.fmt.bufPrint(&buf, fmt, args) catch return TerminalError.WriteFailed;
        try writeAllNative(output);
    }

    // ========================================================================
    // VTable implementation
    // ========================================================================

    /// Get VTable for Terminal interface
    pub fn vtable() TerminalVTable {
        return .{
            .deinit = vtableDeinit,
            .clearScreen = vtableClearScreen,
            .clearLine = vtableClearLine,
            .moveCursor = vtableMoveCursor,
            .hideCursor = vtableHideCursor,
            .showCursor = vtableShowCursor,
            .getWindowSize = vtableGetWindowSize,
            .writeAll = vtableWriteAll,
            .print = vtablePrint,
        };
    }

    /// Create Terminal wrapper
    pub fn terminal(self: *Self) Terminal {
        return Terminal.init(self, @constCast(&vtable()));
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.disableRawMode();
    }

    fn vtableClearScreen(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.clearScreen();
    }

    fn vtableClearLine(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.clearLine();
    }

    fn vtableMoveCursor(ptr: *anyopaque, row: usize, col: usize) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.moveCursor(row, col);
    }

    fn vtableHideCursor(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.hideCursor();
    }

    fn vtableShowCursor(ptr: *anyopaque) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.showCursor();
    }

    fn vtableGetWindowSize(ptr: *anyopaque) TerminalError!WindowSize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.getWindowSize();
    }

    fn vtableWriteAll(ptr: *anyopaque, s: []const u8) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.writeAll(s);
    }

    fn vtablePrint(ptr: *anyopaque, fmt: []const u8, args: anytype) TerminalError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = fmt;
        // Note: In VTable, we lose compile-time format checking
        // This is a simplified implementation
        _ = self;
        _ = args;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "NativeTerminal - enable raw mode" {
    const term = NativeTerminal.enableRawMode() catch |err| {
        try std.testing.expect(err == TerminalError.NotATTY);
        return;
    };
    defer term.disableRawMode();

    var t = term;
    try t.moveCursor(1, 1);
    try t.clearScreen();
}

test "Terminal - interface wrapper" {
    var native = NativeTerminal.enableRawMode() catch |err| {
        try std.testing.expect(err == TerminalError.NotATTY);
        return;
    };
    defer native.disableRawMode();

    const term = native.terminal();
    _ = term;
}
