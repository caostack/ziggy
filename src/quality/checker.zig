//! 代码质量检查框架
//! 提供静态代码分析和质量检查

const std = @import("std");
const mem = std.mem;
const fs = std.fs;

const MAX_CHECKERS = 16;
const MAX_RESULTS = 1024;

/// 检查结果
pub const CheckResult = struct {
    name: []const u8,
    passed: bool,
    message: []const u8,
    file: ?[]const u8 = null,
    line: ?usize = null,
    column: ?usize = null,

    pub fn format(
        self: CheckResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const icon = if (self.passed) "✓" else "✗";
        const color = if (self.passed) "\x1b[32m" else "\x1b[31m";
        const reset = "\x1b[0m";

        try writer.print("{s}{s}{s} {s}", .{ color, icon, reset, self.name });

        if (!self.passed) {
            try writer.print(" - {s}", .{self.message});
            if (self.file) |file| {
                try writer.print(" ({s}", .{file});
                if (self.line) |line| {
                    try writer.print(":{}", .{line});
                }
                try writer.writeAll(")");
            }
        }
    }
};

/// 检查器接口
pub const Checker = struct {
    name: []const u8,
    check_fn: *const fn (allocator: mem.Allocator, source: []const u8, filename: []const u8) anyerror!CheckResult,

    pub fn init(
        name: []const u8,
        check_fn: *const fn (allocator: mem.Allocator, source: []const u8, filename: []const u8) anyerror!CheckResult,
    ) Checker {
        return .{
            .name = name,
            .check_fn = check_fn,
        };
    }

    pub fn run(self: Checker, allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
        return self.check_fn(allocator, source, filename);
    }
};

/// 质量门禁
pub const QualityGate = struct {
    allocator: mem.Allocator,
    checkers: *[MAX_CHECKERS]Checker,
    checker_count: usize,
    results: *[MAX_RESULTS]CheckResult,
    result_count: usize,

    pub fn init(allocator: mem.Allocator) !QualityGate {
        const checkers = try allocator.create([MAX_CHECKERS]Checker);
        errdefer allocator.destroy(checkers);

        const results = try allocator.create([MAX_RESULTS]CheckResult);
        errdefer allocator.destroy(results);

        return .{
            .allocator = allocator,
            .checkers = checkers,
            .checker_count = 0,
            .results = results,
            .result_count = 0,
        };
    }

    pub fn deinit(self: *QualityGate) void {
        self.allocator.destroy(self.checkers);
        self.allocator.destroy(self.results);
    }

    pub fn addChecker(self: *QualityGate, checker: Checker) !void {
        if (self.checker_count >= MAX_CHECKERS) return error.TooManyCheckers;
        self.checkers[self.checker_count] = checker;
        self.checker_count += 1;
    }

    pub fn checkFile(self: *QualityGate, path: []const u8) !void {
        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        const source = try file.readToEndAlloc(self.allocator, 1024 * 1024 * 10); // 10MB limit
        defer self.allocator.free(source);

        const filename = std.fs.path.basename(path);

        for (0..self.checker_count) |i| {
            const checker = self.checkers[i];
            const result = try checker.run(self.allocator, source, filename);
            if (self.result_count < MAX_RESULTS) {
                self.results[self.result_count] = result;
                self.result_count += 1;
            }
        }
    }

    pub fn checkDirectory(self: *QualityGate, dir_path: []const u8) !void {
        var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.path, ".zig")) {
                // 构建完整路径
                const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.path });
                defer self.allocator.free(full_path);

                self.checkFile(full_path) catch |err| {
                    std.debug.print("警告: 检查文件 {s} 失败: {any}\n", .{ full_path, err });
                };
            }
        }
    }

    pub fn report(self: *QualityGate, file: std.fs.File) !void {
        _ = file;
        // 暂时简化输出
        std.debug.print("\n📊 质量检查报告\n", .{});
        std.debug.print("================\n\n", .{});

        var passed: usize = 0;
        var failed: usize = 0;

        for (self.results[0..self.result_count]) |result| {
            if (result.passed) passed += 1 else failed += 1;

            const icon = if (result.passed) "✓" else "✗";
            std.debug.print("  {s} {s}", .{ icon, result.name });

            if (!result.passed) {
                std.debug.print(" - {s}", .{result.message});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("\n================\n", .{});
        std.debug.print("总计: {} 检查, {} 通过, {} 失败\n", .{ self.result_count, passed, failed });
    }

    pub fn hasFailures(self: *const QualityGate) bool {
        for (self.results[0..self.result_count]) |result| {
            if (!result.passed) return true;
        }
        return false;
    }
};
