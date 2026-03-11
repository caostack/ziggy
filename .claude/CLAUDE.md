# Ziggy 项目规范

Zig 终端编辑器项目的开发规范与约定。

## 扩展文档

以下文件作为本文档的扩展：

- `.claude/memory/zig.md` - Zig 语言学习笔记、踩坑记录和最佳实践

---

## 技术栈

| 属性 | 值 |
|------|-----|
| 语言 | Zig 0.15.2+ |

---

## Zig 语言规范

### 内存安全

- **显式分配/释放** - allocator 显式传递，不用全局分配器
- **defer** - 正常路径资源释放
- **errdefer** - 错误路径资源释放

```zig
fn example(allocator: std.mem.Allocator) !void {
    var buf = try allocator.alloc(u8, 100);
    errdefer allocator.free(buf);  // 错误时释放
    defer allocator.free(buf);      // 正常结束时释放
    // ...
}
```

### 错误处理

- **try** - 自动传播错误
- **catch** - 处理错误，提供默认值或恢复

```zig
const result = try mightFail();           // 传播错误
const result = mightFail() catch 0;       // 提供默认值
const result = mightFail() catch |err| {  // 精确处理
    std.log.err("failed: {}", .{err});
    return err;
};
```

### 类型安全

- **限制 anytype** - 只在泛型必要时使用
- **限制 @ptrCast** - 仅用于底层互操作
- **限制 @intCast** - 确保范围检查或已验证

### 并发安全

- **mutex** - 互斥锁保护共享数据
- **atomic** - 原子操作用于无锁场景

---

## Agent 工作流

### 理解优先

- **先读代码再改** - 不理解上下文不动手
- **小批量快反馈** - 改一个模块 → 编译测试
- **显式优于隐式** - 分配/错误/类型都要显式

### 小步迭代，快速验证

```bash
zig build && zig build test    # 改完立即验证
```

- **改一点，测一点** - 每次修改后立即验证
- **先跑通，再优化** - 先让功能工作，再考虑性能

### Zig 编译器是你的朋友

- 编译错误通常很精准，仔细读错误信息
- 利用增量编译，快速迭代
- 不确定语法时，先写最小示例验证

### 查询标准库

遇到标准库 API 问题时，直接看源码：

```bash
zig env    # 找到 zig 安装目录
```

标准库路径：`<zig安装目录>/lib/std/`

- 源码即文档，阅读 `.zig` 文件了解 API 用法
- 版本间 API 可能变化，以本地源码为准

---

## 质量门禁

```bash
zig build && zig build test && zig fmt --check .
```

---

## 常见陷阱

| 陷阱 | 说明 | 预防 |
|------|------|------|
| 内存泄漏 | 忘记 free | 每个 alloc 对应 free，用 defer |
| Use After Free | 释放后继续使用 | free 后置 null，或缩小作用域 |
| 数据竞争 | 多线程访问共享数据 | mutex 保护或 atomic 操作 |

---

## 性能考量

- **先正确再优化** - 健壮性 > 性能
- **善用 comptime** - 零成本抽象，编译时计算

---

## 代码风格

- allocator 显式传递
- 资源释放用 `defer` / `errdefer`
- 文档注释用 `//!`（模块级）和 `///`（函数级）
- 格式化字符串：`{s}` 字符串，`{any}` 通用，`{d}` 数字

### ArrayList 用法 (Zig 0.15)

```zig
var list: std.ArrayList(T) = .{};  // 空初始化
defer list.deinit(allocator);       // 需要 allocator
try list.append(allocator, item);   // 每次操作需要 allocator
```

---

## 参考资源

- [zig.md](memory/zig.md) - Zig 语言学习笔记和踩坑记录
- `.learning/zig/mastery/artifacts/` - Zig 学习代码
