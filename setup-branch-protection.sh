#!/usr/bin/env bash
# Setup Branch Protection for Ziggy
# 配置分支保护以强制执行质量门禁

set -e

echo "🔒 配置 Ziggy 分支保护"
echo "===================="
echo ""

echo "⚠️  此脚本需要在 GitHub 仓库设置中手动完成"
echo ""
echo "📋 步骤："
echo ""
echo "1. 打开浏览器访问："
echo "   https://github.com/caostack/ziggy/settings/branches"
echo ""
echo "2. 找到 'main' 分支，点击编辑按钮"
echo ""
echo "3. 启用以下保护规则："
echo "   ✅ Require a pull request before merging (需要 PR 才能合并)"
echo "   ✅ Require status checks to pass before merging (需要状态检查通过)"
echo ""
echo "4. 在 'Require status checks to pass before merging' 中，选择必需的检查："
echo "   ☑️ quality-gate / Quality Gate (Required)"
echo "   ☑️ philosophy-check / Zig Philosophy Verification"
echo ""
echo "5. 保存设置"
echo ""

echo "🎯 设置完成后："
echo "- 所有提交到 main 的 PR 都会运行质量门禁"
echo "- 质量门禁失败时，PR 无法合并"
echo "- 确保代码符合 Zig 设计哲学"
echo ""

echo "📊 查看 CI 状态："
echo "https://github.com/caostack/ziggy/actions"
echo ""

echo "🔗 或者使用 gh CLI 配置："
echo ""
echo "gh repo edit caostack/ziggy --enable-branch-protection main"
echo ""

echo "✅ 配置完成后，质量门禁将真正强制执行！"
