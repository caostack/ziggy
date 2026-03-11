//! 具体的代码质量检查器

const std = @import("std");
const mem = std.mem;
const Checker = @import("checker.zig").Checker;
const CheckResult = @import("checker.zig").CheckResult;
const QualityGate = @import("checker.zig").QualityGate;

/// 检查资源获取后是否有 defer 清理
pub fn checkDeferCleanup(allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
    _ = allocator;

    var lines = mem.splitScalar(u8, source, '\n');
    var line_num: usize = 0;

    // 简单的栈跟踪 defer 配对
    var defer_stack: [32]usize = undefined;
    var defer_stack_len: usize = 0;

    while (lines.next()) |line| {
        line_num += 1;

        // 检查资源获取模式
        const resource_patterns = [_][]const u8{
            "openFile",
            "openDir",
            "openIterableDir",
            "alloc",
            "create",
            "dup()",
        };

        var found_resource = false;
        for (resource_patterns) |pattern| {
            if (mem.indexOf(u8, line, pattern)) |_| {
                // 检查是否有 try 或 如果在赋值
                if (mem.indexOf(u8, line, "try ") != null or
                    mem.indexOf(u8, line, "const ") != null or
                    mem.indexOf(u8, line, "var ") != null)
                {
                    found_resource = true;
                    break;
                }
            }
        }

        if (found_resource) {
            // 查找当前行之后的 defer（在同一个作用域）
            if (defer_stack_len < defer_stack.len) {
                defer_stack[defer_stack_len] = line_num;
                defer_stack_len += 1;
            }
        }

        // 检查是否有 defer
        if (mem.indexOf(u8, line, "defer")) |_| {
            if (defer_stack_len > 0) {
                defer_stack_len -= 1;
            }
        }
    }

    if (defer_stack_len > 0) {
        const issue = defer_stack[0];
        return CheckResult{
            .name = "资源清理检查",
            .passed = false,
            .message = "可能缺少 defer 清理资源",
            .file = filename,
            .line = issue,
            .column = null,
        };
    }

    return CheckResult{
        .name = "资源清理检查",
        .passed = true,
        .message = "所有资源都有 defer 清理",
    };
}

/// 检查是否使用隐藏分配（ArrayList 等）
pub fn checkHiddenAllocation(allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
    _ = allocator;

    const hidden_alloc_patterns = [_][]const u8{
        "ArrayList",
        "HashMap",
        "BoundedMap",
        "AutoHashMap",
    };

    var line_num: usize = 0;
    var lines = mem.splitScalar(u8, source, '\n');

    while (lines.next()) |line| : (line_num += 1) {
        // 跳过注释
        const trimmed = mem.trim(u8, line, " \t\r");
        if (mem.startsWith(u8, trimmed, "//")) continue;

        for (hidden_alloc_patterns) |pattern| {
            if (mem.indexOf(u8, line, pattern)) |_| {
                return CheckResult{
                    .name = "隐藏分配检查",
                    .passed = false,
                    .message = "使用可能导致隐藏分配的类型",
                    .file = filename,
                    .line = line_num + 1,
                    .column = mem.indexOf(u8, line, pattern),
                };
            }
        }
    }

    return CheckResult{
        .name = "隐藏分配检查",
        .passed = true,
        .message = "没有使用隐藏分配",
    };
}

/// 检查错误处理
pub fn checkErrorHandling(allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
    _ = allocator;

    // 检查是否使用 catch 而不是 try
    var line_num: usize = 0;
    var lines = mem.splitScalar(u8, source, '\n');
    var has_catch_without_try = false;

    while (lines.next()) |line| : (line_num += 1) {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (mem.startsWith(u8, trimmed, "//")) continue;

        // 检查 catch 但没有 try（可能在吞掉错误）
        if (mem.indexOf(u8, line, "catch")) |_| {
            if (mem.indexOf(u8, line, "try") == null and
                mem.indexOf(u8, line, "|") == null)
            {
                // 检查是否是空的 catch 块
                if (mem.indexOf(u8, line, "catch {}") != null or
                    mem.indexOf(u8, line, "catch unreachable") != null)
                {
                    has_catch_without_try = true;
                    break;
                }
            }
        }
    }

    if (has_catch_without_try) {
        return CheckResult{
            .name = "错误处理检查",
            .passed = false,
            .message = "发现空的 catch 块，可能吞掉错误",
            .file = filename,
        };
    }

    return CheckResult{
        .name = "错误处理检查",
        .passed = true,
        .message = "错误处理看起来合理",
    };
}

/// 检查代码风格
pub fn checkCodeStyle(allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
    _ = allocator;

    var line_num: usize = 0;
    var lines = mem.splitScalar(u8, source, '\n');

    var issue_count: usize = 0;
    var first_issue: []const u8 = "";

    while (lines.next()) |line| : (line_num += 1) {
        // 跳过注释
        const trimmed = mem.trim(u8, line, " \t\r");
        if (mem.startsWith(u8, trimmed, "//")) continue;

        // 检查行长度
        if (line.len > 120) {
            if (issue_count == 0) first_issue = "行长度超过 120 字符";
            issue_count += 1;
        }

        // 检查尾随空格
        if (line.len > 0 and line[line.len - 1] == ' ') {
            if (issue_count == 0) first_issue = "尾随空格";
            issue_count += 1;
        }

        // 检查 tab 字符（应该用空格）
        if (mem.indexOf(u8, line, "\t")) |_| {
            if (issue_count == 0) first_issue = "使用 tab 而非空格";
            issue_count += 1;
        }
    }

    if (issue_count > 0) {
        return CheckResult{
            .name = "代码风格检查",
            .passed = false,
            .message = first_issue,
            .file = filename,
        };
    }

    return CheckResult{
        .name = "代码风格检查",
        .passed = true,
        .message = "代码风格符合规范",
    };
}

/// 检查是否使用 std.debug.print（应该用 logging）
pub fn checkDebugPrint(allocator: mem.Allocator, source: []const u8, filename: []const u8) !CheckResult {
    _ = allocator;

    if (mem.indexOf(u8, source, "std.debug.print")) |_| {
        return CheckResult{
            .name = "调试代码检查",
            .passed = false,
            .message = "使用 std.debug.print（应该移除或替换为 logging）",
            .file = filename,
        };
    }

    return CheckResult{
        .name = "调试代码检查",
        .passed = true,
        .message = "没有调试打印语句",
    };
}

/// 注册所有检查器
pub fn registerAllCheckers(gate: *QualityGate, allocator: mem.Allocator) !void {
    _ = allocator;
    try gate.addChecker(Checker.init("defer 清理检查", checkDeferCleanup));
    try gate.addChecker(Checker.init("隐藏分配检查", checkHiddenAllocation));
    try gate.addChecker(Checker.init("错误处理检查", checkErrorHandling));
    try gate.addChecker(Checker.init("代码风格检查", checkCodeStyle));
    try gate.addChecker(Checker.init("调试代码检查", checkDebugPrint));
}
