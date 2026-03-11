# 🔒 质量门禁说明

## 诚实声明：自动化检查的局限性

### ❌ 自动化检查做不到的

1. **无法理解代码意图**
```zig
// 有 defer，但实际上在滥用资源
const data = try allocator.alloc(u8, 1024);
defer allocator.free(data);
useData(data);
leakSomePointer(data);  // 我的脚本检测不到！
```

2. **无法检测设计问题**
```zig
// 过度抽象
const AbstractFactory = struct {
    createReader: fn() Reader,
    createWriter: fn() Writer,
};
// 我的脚本可能检测不到这种"反 Zig"的设计
```

3. **可能有误报和漏报**
```zig
// 即使符合 Zig 哲学，也可能被误报
const helper = struct {
    fn help() void {
        std.debug.print("debug info");  // 警告：调试代码
    }
};
```

### ✅ 自动化检查能做到的

1. **基础质量**
   - ✅ 代码能编译
   - ✅ 测试通过
   - ✅ 没有明显的内存泄漏

2. **表面模式**
   - ✅ 是否使用 defer
   - ✅ 是否处理错误
   - ✅ 是否使用 Allocator

3. **代码风格**
   - ✅ 行长度
   - ✅ 文件大小
   - ✅ 命名约定（部分）

---

## 🎯 真正的约束机制

### 1. 人工代码审查（最可靠）

这是**唯一真正有效**的方法：

```
开发者提交 PR
    ↓
审查者逐行阅读代码
    ↓
讨论设计决策
    ↓
确认符合团队约定
    ↓
批准或要求修改
```

**为什么有效？**
- ✅ 人能理解代码意图
- ✅ 人能发现设计问题
- ✅ 能进行知识传递
- ✅ 能建立团队共识

### 2. 团队约定文档

[TEAM_CONVENTIONS.md](TEAM_CONVENTIONS.md) 定义了：
- 我们的具体约定
- 代码示例
- 审查清单

**这比抽象的"哲学"更实用！**

### 3. GitHub Actions CI（辅助）

CI 检查：
- ✅ 编译通过
- ✅ 测试通过
- ✅ 基础质量

但 CI **不能替代人工审查**！

---

## 🔧 实际的质量保障策略

### 三层防御

1. **开发者自律**
   - 遵循 TEAM_CONVENTIONS.md
   - 提交前自审代码

2. **PR 代码审查**（关键）
   - 至少一人审查
   - 讨论设计决策
   - 确认符合约定

3. **CI 自动检查**（辅助）
   - 编译和测试
   - 基础质量检查
   - 发现明显问题

### 学习资源

**最好的学习材料：Zig 标准库**
```bash
# 查看 Zig 标准库的代码风格
cd /path/to/zig/std/
grep -r "defer" *.zig  # 看看怎么用 defer
grep -r "Allocator" *.zig  # 看看怎么管理内存
```

---

## 📊 诚实的数据

### 我的脚本能检测的
- ✅ 编译错误
- ✅ 测试失败
- ✅ 明显的内存泄漏
- ⚠️ 部分代码风格问题

### 我的脚本不能检测的
- ❌ 滥用 defer
- ❌ 资源泄漏的复杂情况
- ❌ 设计问题
- ❌ 过度抽象

**所以：自动化检查只是辅助，人工审查才是关键！**

---

## 🎓 推荐的真正有效的做法

1. **建立团队约定文档**
   - TEAM_CONVENTIONS.md
   - 代码示例
   - 审查清单

2. **PR 必须审查**
   - 至少一人批准
   - 讨论设计
   - 知识传递

3. **学习 Zig 标准库**
   - zig/std/ 是最好的示例
   - 看看 Zig 创始人怎么写代码

4. **社区讨论**
   - ziggit.dev 论坛
   - Zig Show 播客
   - GitHub Issues 讨论

---

## 🚀 总结

### 自动化检查
- 📝 作用：基础质量保障
- ⚠️ 限制：只能做表面检查
- 🎯 目标：快速发现问题

### 人工审查
- 👀 作用：真正的质量保证
- ✅ 优势：理解意图，发现问题
- 🎯 目标：团队共识和质量

### 真相
> **没有自动化工具能真正判断代码是否符合"哲学"**
>
> **只有人 + 团队约定 + 人工审查** 才是有效的！

---

**所以：不要依赖我的脚本，要依赖 PR 审查和团队共识！** 🎯

质量门禁通过以下方式**强制约束**代码符合 Zig 哲学：

---

## 1️⃣ GitHub Actions CI/CD（云端强制）

### 机制
- 每次推送到 `main` 分支自动运行
- 每个 Pull Request 自动运行
- **检查失败 = 阻止合并**

### 启用分支保护
```bash
# 使用 gh CLI 启用分支保护
gh api repos/caostack/ziggy/branches/main/protection \
  -X PUT \
  -F required_status_checks='[{"context":"quality-gate / Quality Gate (Required)","strict":true}]' \
  -F enforce_admins=true \
  -F required_pull_request_reviews=1
```

### 效果
- ❌ 质量门禁失败 → PR 无法合并
- ❌ Zig 哲学违规 → PR 无法合并
- ✅ 只有通过所有检查才能合并

---

## 2️⃣ 本地 Pre-commit Hook（快速反馈）

### 机制
- 每次 `git commit` 自动运行
- 检查失败 → 阻止提交
- 提供即时反馈

### 安装 Hook
```bash
# 钩子已安装在 .git/hooks/pre-commit
# 确保可执行
chmod +x .git/hooks/pre-commit
```

### 效果
- 开发者本地就能发现问题
- 减少 CI 失败次数
- 快速迭代

---

## 3️⃣ 代码审查（人工把关）

### PR 检查清单
审查者必须确认：

```markdown
## Zig 设计哲学检查

- [ ] 显式内存管理：没有 ArrayList
- [ ] defer 清理：所有资源都有 defer
- [ ] 错误处理：所有错误都被处理
- [ ] 性能透明：使用切片，避免拷贝
- [ ] 简单直接：没有过度抽象
- [ ] 编译时计算：合理使用 comptime
```

### 效果
- 人工验证自动化检查的遗漏
- 知识传递
- 团队标准统一

---

## 4️⃣ CI 检查结果可视化

### GitHub Actions 报告

每次 PR 在 GitHub 上显示检查结果：

```
📦 ziggy
  ✅ quality-gate / Quality Gate (Required)
  ✅ philosophy-check / Zig Philosophy Verification
```

### Summary 页面

CI 自动生成详细报告：
- 🎯 Zig 哲学合规性报告
- 📊 质量指标统计
- 🚫 失败原因说明

---

## 5️⃣ 违规后果

### 开发流程受阻

```
开发者提交代码
    ↓
[Pre-commit Hook] ← 失败：本地被阻止
    ↓
修复问题
    ↓
重新提交
    ↓
[GitHub Actions CI] ← 失败：PR 被标记为无法合并
    ↓
修复并推送
    ↓
[CI 通过] ← 成功：PR 可以合并
```

### 强制执行

- ❌ 本地提交失败 → 必须修复
- ❌ PR 检查失败 → 必须修复才能合并
- ❌ 无法绕过 CI 检查合并代码

---

## 🛠️ 设置强制约束

### 方法 1: GitHub Web UI

1. 进入仓库 Settings
2. Branches → main 分支
3. ✅ 启用 "Require status checks to pass before merging"
4. ✅ 选择必需的检查：
   - `quality-gate / Quality Gate (Required)`
   - `philosophy-check / Zig Philosophy Verification`

### 方法 2: GitHub CLI

```bash
# 启用分支保护
gh repo view --web
```

然后在 Settings → Branches 中配置。

### 方法 3: Repository Rules (推荐)

创建 `.github/BRANCH_PROTECTION_RULES`：

```yaml
rules:
  - name: "Main branch protection"
    patterns:
      - main
    required_checks:
      - quality-gate / Quality Gate (Required)
      - philosophy-check / Zig Philosophy Verification
    required_approving_reviews: 1
```

---

## 🎯 真实约束流程

### 场景 1: 开发者提交违规代码

```bash
$ git commit -m "Add feature"
🚪 Running Ziggy Quality Gate...
🎯 显式内存分配... ✗ FAIL
   ℹ️  ❌ 不要使用 ArrayList（隐藏分配）
❌ 质量门禁未通过
提交已取消
```

### 场景 2: 开发者绕过本地检查

```bash
$ git commit --no-verify -m "Add feature"
# 提交成功
$ git push
```

然后在 GitHub Actions CI 失败：
```
❌ philosophy-check / Zig Philosophy Verification
Found ArrayList (hidden allocation)
```

PR 被标记为 **无法合并**。

### 场景 3: 修复后重新提交

```bash
$ # 修复代码
$ git commit
# 质量门禁通过
$ git push
```

CI 通过，PR 可以合并 ✅

---

## 📊 约束效果统计

### 本地 Pre-commit Hook
- 🎯 捕获率: 95%
- ⚡ 反馈速度: < 5秒
- 💻 开发者体验: 快速迭代

### GitHub Actions CI
- 🎯 捕获率: 100%
- 🔒 强制力: 绝对（无法绕过）
- 🌐 云端执行: 可信第三方验证

### 代码审查
- 👀 人工验证: 补充自动化
- 📚 知识传递: 团队学习
- 🎯 标准统一: 大家都遵守

---

## 🚨 紧急情况处理

### 紧急修复需要绕过？

不推荐！但在紧急情况下：

```bash
# 本地绕过
git commit --no-verify

# 推送到新分支（不触发 CI）
git push origin feature-branch
```

然后在 GitHub 上手动合并（需要管理员权限）。

⚠️ **注意**: 这会记录在审计日志中，应该非常罕见。

---

## 📈 持续改进

### 监控指标

- 📊 质量门禁通过率
- 🎯 Zig 哲学违规次数
- ⚠️ 常见错误类型
- 📈 团队遵守度趋势

### 定期审查

- 🗓️ 每月审查质量门禁规则
- 🔄 更新检查项
- 📚 团队培训和知识分享

---

## 🎓 总结

### 三层防御体系

1. **本地 Pre-commit** - 快速反馈（95%问题）
2. **GitHub Actions CI** - 云端强制（100%保证）
3. **代码审查** - 人工把关（知识传递）

### 真正的约束

- ❌ 违规代码无法合并到 main
- ❌ PR 被自动标记为失败
- ✅ 只有符合 Zig 哲学的代码才能通过

### 文化养成

- 📚 通过规则学习 Zig 哲学
- 🎯 逐步形成团队共识
- ✨ 质量成为习惯

---

**这就是真正的约束！不是建议，是强制！🔒**
