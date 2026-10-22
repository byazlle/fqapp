# remote/ — 运行时远程配置

这个目录下的文件随仓库分发，客户端在运行时通过 raw.githubusercontent.com 拉取。
**改这里 + 推送 = 对所有已安装用户生效，不需要重新发版。**

拉取地址固定为仓库默认分支 `winFQAPP`：

```
https://raw.githubusercontent.com/byazlle/winFQAPP/winFQAPP/remote/source_blocklist.json
```

## source_blocklist.json — 第三方源屏蔽名单

万一某家第三方源（CMS / 西饭 / 河马）的地址失效、挂掉或不再适合继续提供，
把对应标识加进名单并推送到 master，客户端下次启动（或打开「设置 → 内容源」）时
就会自动停用该源：不可选、不进自动容错链、也不能新增同主机的自定义源，
设置页里显示「已停用」。番茄内置源不受影响。

字段：

| 字段 | 说明 |
| --- | --- |
| `sourceIds` | 源 ID 列表。内置源：`builtin:xifan`（西饭）、`builtin:hema`（河马）、`builtin:hongguo`（红果网页版） |
| `hosts` | 主机名列表（小写、不含端口与路径）。命中自定义 CMS 源的 `baseUrl` 主机（含子域名） |
| `message` | 停用原因，展示给用户；留空则用默认文案 |
| `version` / `updatedAt` | 仅备忘，客户端不校验 |

示例：西饭与河马整体停用。

```json
{
  "version": 2,
  "updatedAt": "2026-10-22",
  "message": "西饭/河马线路维护中，暂时停用，请改用其他来源",
  "sourceIds": ["builtin:xifan", "builtin:hema"],
  "hosts": ["youlishipin.com", "kuaikaw.cn"]
}
```

只停用某条 CMS 线路（例如 example.com 挂了）：

```json
{
  "version": 2,
  "updatedAt": "2026-10-22",
  "message": "该 CMS 线路暂时不可用",
  "sourceIds": [],
  "hosts": ["example.com"]
}
```

恢复：把对应项从数组里删掉再推送即可。

注意：

- 名单只收紧不放宽。用户本地手动打开的源，只要命中名单一样停用。
- 拉取失败（断网、404、文件损坏）时客户端用上一次成功的名单；没有缓存则不停用任何源。
- 改完推送后建议抽查一次 Release 页最新版的「设置 → 内容源」显示是否符合预期。
