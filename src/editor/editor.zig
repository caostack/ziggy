//! Main editor orchestration - event loop and key handling
const std = @import("std");
const Allocator = std.mem.Allocator;

const Terminal = @import("terminal.zig").Terminal;
const Buffer = @import("buffer.zig").Buffer;
const Screen = @import("screen.zig").Screen;
const Input = @import("input.zig").Input;
const FileIO = @import("file_io.zig").FileIO;
const Key = @import("input.zig").Key;
const TerminalError = @import("terminal.zig").TerminalError;

pub const EditorError = error{
    Quit,
    SaveFailed,
    OpenFailed,
    OutOfMemory,
};

pub const Editor = struct {
    allocator: Allocator,
    terminal: Terminal,
    buffer: *Buffer,
    screen: Screen,
    input: Input,
    filename: ?[]const u8,
    modified: bool,
    should_quit: bool,

    pub fn init(allocator: Allocator, filename: ?[]const u8) !Editor {
        // Enable raw mode
        const terminal = try Terminal.enableRawMode();
        errdefer terminal.disableRawMode();

        // Initialize buffer
        const initial_capacity = 4096;
        var buffer = try allocator.create(Buffer);
        errdefer allocator.destroy(buffer);

        buffer.* = try Buffer.init(allocator, initial_capacity);
        errdefer buffer.deinit();

        // Load file if provided
        var loaded_content: ?[]const u8 = null;
        if (filename) |path| {
            const content = FileIO.open(allocator, path) catch {
                return EditorError.OpenFailed;
            };
            loaded_content = content;

            // Insert content into buffer line by line
            var lines_iter = std.mem.splitScalar(u8, content, '\n');
            while (lines_iter.next()) |line| {
                try buffer.insert(line);
                if (lines_iter.index == 0) {
                    // Don't add newline for last line if file doesn't end with one
                    if (content.len > 0 and content[content.len - 1] == '\n') {
                        try buffer.insert("\n");
                    }
                } else {
                    try buffer.insert("\n");
                }
            }
        }

        if (loaded_content) |content| {
            allocator.free(content);
        }

        // Initialize screen
        const screen = try Screen.init(@constCast(&terminal));

        return .{
            .allocator = allocator,
            .terminal = terminal,
            .buffer = buffer,
            .screen = screen,
            .input = Input.init(),
            .filename = filename,
            .modified = false,
            .should_quit = false,
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buffer.deinit();
        self.allocator.destroy(self.buffer);
        self.terminal.disableRawMode();
    }

    /// Main event loop
    pub fn run(self: *Editor) !void {
        while (!self.should_quit) {
            // Refresh screen
            self.screen.refresh(self.buffer, self.filename, self.modified) catch |err| {
                // If refresh fails, try to restore terminal and exit
                return err;
            };

            // Read key
            const key = self.input.readKey() catch continue;

            // Handle key
            self.handleKey(key) catch |err| {
                if (err == EditorError.Quit) {
                    self.should_quit = true;
                }
            };
        }
    }

    fn handleKey(self: *Editor, key: Key) !void {
        switch (key) {
            .ctrl_c => {
                // Force quit (no prompt)
                self.should_quit = true;
            },
            .ctrl_q => {
                // Quit with prompt if modified
                if (self.modified) {
                    try self.promptSave();
                } else {
                    self.should_quit = true;
                }
            },
            .ctrl_s => {
                // Save file
                try self.saveFile();
            },
            .arrow_up => {
                if (self.buffer.moveUp()) {
                    self.screen.scrollIfNeeded(self.buffer);
                }
            },
            .arrow_down => {
                if (self.buffer.moveDown()) {
                    self.screen.scrollIfNeeded(self.buffer);
                }
            },
            .arrow_left => {
                _ = self.buffer.moveLeft();
            },
            .arrow_right => {
                _ = self.buffer.moveRight();
            },
            .home => {
                // Move to start of line
                self.buffer.cursor_col = 0;
            },
            .end => {
                // Move to end of line
                self.buffer.cursor_col = self.buffer.getLineLength(self.buffer.cursor_row);
            },
            .enter => {
                try self.buffer.insert("\n");
                self.modified = true;
                self.screen.scrollIfNeeded(self.buffer);
            },
            .backspace => {
                if (self.buffer.delete()) {
                    self.modified = true;
                }
            },
            .delete => {
                // Delete key - delete character at cursor (after cursor)
                // For now, just ignore as our gap buffer doesn't support this yet
                _ = self.buffer.getCharAtCursor();
            },
            .character => |bytes| {
                // Find actual length of UTF-8 sequence
                const len = std.mem.sliceTo(bytes[0..], 0).len;
                if (len == 0) {
                    // Empty character, shouldn't happen
                    return;
                }
                try self.buffer.insert(bytes[0..len]);
                self.modified = true;
            },
            .escape, .tab, .page_up, .page_down => {
                // Ignore for now
            },
            .ctrl_f, .unknown => {
                // Ignore for now
            },
        }
    }

    fn saveFile(self: *Editor) !void {
        const path = self.filename orelse {
            // No filename - can't save
            return EditorError.SaveFailed;
        };

        const content = self.buffer.toSlice();
        FileIO.save(path, content) catch {
            return EditorError.SaveFailed;
        };

        self.modified = false;

        // Show save message on status line temporarily
        self.screen.terminal.moveCursor(self.screen.window_rows, 1) catch {};
        self.screen.terminal.writeAll("\x1b[7m") catch {}; // Invert colors
        self.screen.terminal.writeAll(" Saved! ") catch {};
        self.screen.terminal.writeAll("\x1b[m") catch {}; // Reset colors
    }

    fn promptSave(self: *Editor) !void {
        // Simple prompt: "Save changes? (y/n)"
        const prompt = "Save changes? (y/n) ";

        // Move to status line
        self.screen.terminal.moveCursor(self.screen.window_rows, 1) catch {};
        self.screen.terminal.writeAll("\x1b[7m") catch {}; // Invert colors
        self.screen.terminal.writeAll(prompt) catch {};
        self.screen.terminal.writeAll("\x1b[m") catch {}; // Reset colors

        // Read response
        var buf: [1]u8 = undefined;
        const n = self.input.stdin_file.read(&buf) catch return error.ReadFailed;
        if (n != 1) return error.ReadFailed;

        const response = buf[0];
        if (response == 'y' or response == 'Y') {
            try self.saveFile();
        }

        self.should_quit = true;
    }
};

test "editor init" {
    // This test requires a terminal, so we'll just test compilation
    // Actual testing will be done during manual integration testing
    const editor = Editor.init(std.testing.allocator, null) catch |err| {
        // Not a TTY in test environment, that's okay
        try std.testing.expect(err == TerminalError.NotATTY);
        return;
    };
    defer editor.deinit();
}
