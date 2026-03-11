# Ziggy 质量门禁 (Quality Gate)

## 🎯 Zig 设计哲学优先

**重要**: 本项目的质量门禁不仅检查代码质量，更严格检查代码是否符合 **Zig 设计哲学**。

核心原则：
1. **显式优于隐式** - 不允许隐藏的分配、错误
2. **手动资源管理** - 必须使用 `defer` 清理资源
3. **编译时计算** - 利用 `comptime` 减少运行时开销
4. **无隐藏分配** - 禁止使用 `ArrayList` 等隐藏分配的类型
5. **性能透明** - 使用切片而非拷贝
6. **简单直接** - 避免 OOP 抽象

详细规范请参阅 [ZIG_PHILOSOPHY.md](ZIG_PHILOSOPHY.md)。

---

## 🚪 什么是质量门禁？

质量门禁是一套自动化检查，确保代码在合并到主分支前达到一定的质量标准。

## 📋 检查项目

### 必须通过 (Mandatory)

1. **✅ 编译检查** - 代码必须能够成功编译
2. **✅ 单元测试** - 所有测试必须通过
3. **✅ 无内存泄漏** - GPA 检测器不得报告内存泄漏

### 警告项 (Warnings)

1. **⚠️ 无临时文件** - 不应包含 `.swp`, `~`, `.tmp` 等临时文件
2. **⚠️ 无遗留 TODO** - 代码中不应有未完成的 TODO/FIXME
3. **⚠️ 无调试代码** - 不应包含 `std.debug.print` 等调试代码
4. **⚠️ 行长度限制** - 单行不超过 100 字符
5. **⚠️ 无超大文件** - 单个 `.zig` 文件不超过 50KB
6. **⚠️ 无敏感信息** - 不应包含密码、密钥等敏感信息

## 🔧 使用方法

### 本地使用

在提交前运行质量门禁：

```bash
./quality-gate.sh
```

### 自动运行

Git pre-commit 钩子会在每次提交时自动运行：

```bash
git commit  # 自动运行质量门禁
```

### CI/CD

GitHub Actions 会在以下情况自动运行：
- 推送到 `main` 或 `develop` 分支
- 创建 Pull Request 到 `main` 分支

## 📏 代码质量标准

### 编码规范

1. **命名约定**
   - 函数名使用 `camelCase`
   - 类型名使用 `PascalCase`
   - 常量名使用 `UPPER_SNAKE_CASE`

2. **注释规范**
   - 公共函数必须有文档注释
   - 复杂逻辑需要解释注释
   - TODO 标记应该转换为 Issue

3. **错误处理**
   - 使用明确的错误集
   - 错误消息要清晰有用
   - 使用 `defer` 确保资源清理

### 架构原则

1. **模块化** - 功能分离到独立模块
2. **可测试性** - 代码易于单元测试
3. **性能考虑** - 关键路径要优化

## 🚨 故障排除

### 质量门禁失败怎么办？

1. 查看失败的检查项
2. 根据提示修复问题
3. 重新运行 `./quality-gate.sh`
4. 确认通过后再提交

### 跳过质量门禁（不推荐）

如果必须跳过（紧急情况）：

```bash
git commit --no-verify
```

⚠️ **注意**: 跳过质量门禁应该非常罕见，需要团队批准。

## 📊 指标监控

当前项目质量指标：

- 📝 代码行数: 自动计算
- 📄 文件数量: 自动计算
- ✅ 测试覆盖率: 手动维护
- 🐛 Bug 数量: 通过 Issues 跟踪

## 🔧 自定义检查

要添加新的质量检查，编辑 `quality-gate.sh` 文件：

```bash
# 添加新的检查函数
check "检查名称" "command_to_run"
```

## 📚 相关资源

- [Zig 编码规范](https://ziglang.org/documentation/master/#Style-Guide)
- [Git Hooks 文档](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
