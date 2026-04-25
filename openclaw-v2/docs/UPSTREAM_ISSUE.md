# 关于 `feishu_seed_workspace_patch.py` 的 upstream tracker

## Why this local patch exists

openclaw 2026.3.28 的 feishu `dynamicAgentCreation` 在创建 peer workspace 时**只 mkdir 空目录**，然后由 workspace bootstrap 流程 `writeFileIfMissing` 塞入 openclaw bundled 的 memorist 默认 persona（"Hey I just came online, who am I?"）。

review-agent 需要的是 review-coach persona。没有官方机制可以让 feishu dynamicAgentCreation 从**自定义源目录**克隆 template（wecom plugin 有这个能力，feishu 原生没有）。

所以我们用 local patch 改 `monitor-*.js` 里 `maybeCreateDynamicAgent` 函数，在 openclaw mkdir 之后、bootstrap seed 之前 `cp -R <our-template> <new-workspace>`，让 `writeFileIfMissing` 发现文件已在就不覆盖。

## Upstream ask

向 openclaw 提 issue/PR 请求：给 feishu `dynamicAgentCreation` schema 加一个 `workspaceTemplateSource` 字段（或给 `workspaceTemplate` 增加"如果是存在的目录就 clone"语义）。语义跟 wecom plugin 对齐:

```json
"channels.feishu.dynamicAgentCreation": {
    "enabled": true,
    "workspaceTemplate": "~/.openclaw/workspace-{agentId}",
    "workspaceTemplateSource": "~/.openclaw/workspace/templates/review-agent",   // 新增
    "maxAgents": 100
}
```

Expected behavior:
- 如果 `workspaceTemplateSource` 未设（当前默认）：跟现在一样，mkdir 空目录
- 如果设了且路径存在：在 mkdir 之后 `cp -R <source>/. <new-workspace>/`
- 如果设了但路径不存在：log warn + fallback 到空 mkdir

相应 upstream code 改动（`monitor-*.js` 里 `maybeCreateDynamicAgent`）:

```js
const workspaceTemplate = dynamicCfg.workspaceTemplate ?? "~/.openclaw/workspace-{agentId}";
const workspaceTemplateSource = dynamicCfg.workspaceTemplateSource;  // NEW
// ...existing mkdir logic...
await fsSync.promises.mkdir(workspace, { recursive: true });
// NEW: clone from source if provided
if (workspaceTemplateSource) {
    const src = resolveUserPath(workspaceTemplateSource);
    if (fsSync.existsSync(src)) {
        const { execSync } = await import("node:child_process");
        try { execSync(`cp -R "${src}/." "${workspace}/"`, { stdio: "ignore" }); }
        catch (e) { log(`workspaceTemplateSource seed failed: ${e}`); }
    }
}
await fsSync.promises.mkdir(agentDir, { recursive: true });
```

## Once merged upstream

当 upstream 合并并发布新版后，review-agent 这边可以:

1. 在 `install.sh` Phase B 把 `feishu_seed_workspace_patch.py` 这一步跳过（检测 openclaw 版本，如果 >= 支持版本则 skip）
2. `patch_openclaw_json.py` 里给 `dynamicAgentCreation` 加 `workspaceTemplateSource` 字段指向 `~/.openclaw/workspace/templates/review-agent`
3. `feishu_seed_workspace_patch.py` 的任何现有 patch 残留由 `--revert` 清掉

## 跟踪状态

- [ ] openclaw 仓库提 issue
- [ ] 写 PR（参考 wecom plugin 的 clone 逻辑）
- [ ] 合并 + 新版发布
- [ ] review-agent 切换到原生 API，删 local patch
- [ ] `docs/FIELD_NOTES.md` 里把 "Bug 2" 标记为已解决

## 当前应对

v2.1.2 的 `feishu_seed_workspace_patch.py` 已经做到:
- 跨 macOS / Linux / 各种 npm 安装位置的 monitor-*.js 自动发现
- 跨 hash-suffix 变化容错（glob + anchor grep）
- 对 `openclaw update` 有 `--revert` 恢复 + 幂等 re-apply

所以 patch 虽然存在，但日常运维不碰——只有 openclaw 升级后需要 re-run 一次 patcher。直到 upstream 合并。
