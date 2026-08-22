# card-web Web 打包与云服务器部署设计

日期：2026-08-22
前置：`2026-08-22-room-match-integration-design.md`（登录/匹配/房间接入，已落地）
服务器：`120.27.241.134`（Alibaba Cloud Linux 4，nginx 1.30.4 + docker compose 已跑 card/user/mysql/redis 全家桶，均健康）

## 1. 目标与非目标

**目标**：本地 CLI 打出 Godot Web 包，部署到服务器 nginx `:8080` 独立 server（同源反代 `/api/v1` 到已运行的 127.0.0.1:8888/8890），公网浏览器可玩：游客登录 → 建房/加入 → 准备/开局（到 `game_started` overlay 为止，与客户端现有功能边界一致）。

**非目标**：后端 CORS 中间件（同源反代后不需要；砍掉此前批准项）、HTTPS/域名、CI、后端容器与配置改动、80 端口 web-console 站点改动。

## 2. 客户端唯一代码改动：AppConfig 同源适配

```gdscript
static func get_base_url() -> String:
	var from_env := OS.get_environment("CARD_API_URL")  # 原生调试覆盖，优先级最高
	if from_env != "":
		return from_env
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin"))
	return DEFAULT_BASE_URL
```

`get_card_base_url()` 同构（env `CARD_CARD_URL`）。效果：web 导出自动同源（`:8080` 页面调 `:8080/api/...`，无 CORS）；编辑器/桌面保持 127.0.0.1 默认；`RoomSocket` 的 ws 地址由 card base 推导（http→ws），自动正确。回归影响：`AppConfig` 单测只断言非空，不受影响；live smoke 用 env 覆盖不受影响。

## 3. 打包（本地）

1. **模板安装（一次性）**：`HTTPS_PROXY=http://127.0.0.1:7890 curl -L` 下载 `Godot_v4.7.2-stable_export_templates.tpz`（GitHub releases，实为 zip），解压 `templates/` 内容到 `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`。
2. **`export_presets.cfg`（新建）**：preset 名 `Web`、platform `Web`、`export_path="export/web/index.html"`、`variant/thread_support=false`（免 COOP/COEP，任意静态服务器可跑）、沿用 gl_compatibility。
3. **导出**：`/Users/dn/bin/godot --headless --export-release "Web"` → `export/web/`（gitignore 已含 `export/`）。

## 4. 服务器部署

- 上传：`rsync -a export/web/ root@120.27.241.134:/var/www/card-web/`
- 新增 `/etc/nginx/conf.d/card-web.conf`（不动 `web-console.conf`）：

```nginx
server {
    listen 8080;
    server_name _;
    root /var/www/card-web;

    location /api/v1/auth/   { proxy_pass http://127.0.0.1:8888; }
    location /api/v1/users/  { proxy_pass http://127.0.0.1:8888; }
    location /api/v1/healthz { proxy_pass http://127.0.0.1:8888; }
    location /api/v1/rooms   { proxy_pass http://127.0.0.1:8890; }
    location /api/v1/match   { proxy_pass http://127.0.0.1:8890; }
    location /api/v1/ws      { proxy_pass http://127.0.0.1:8890;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s; }
}
```

- 生效：`nginx -t && nginx -s reload`
- **安全组放行 8080 由用户在阿里云控制台操作**（工具不可达）；服务器本机 firewalld 若启用则 `firewall-cmd --add-port=8080/tcp`。

## 5. 验证

1. `curl http://120.27.241.134:8080/` 返回 200 且为 Godot 导出页；`curl .../api/v1/healthz` 经反代返回 `{"code":0,...}`
2. 本机指向公网跑 live smoke：`CARD_API_URL=http://120.27.241.134:8080 CARD_CARD_URL=http://120.27.241.134:8080 /Users/dn/bin/godot --headless --script res://tests/live_smoke_room.gd` → 7/7（注册→建房→WS→开局扣费全走公网链路；guest 限流按公网 IP 计）
3. `/browse` 无头浏览器打开 `http://120.27.241.134:8080`：登录页渲染 → 游客登录进主页 → 建房进房间页；控制台无网络/CORS 错误

## 6. 风险与对策

- 模板下载失败（代理不通）：报错并给手动安装指引；不阻塞 AppConfig/nginx 部分
- 8080 安全组未放行：curl/浏览器超时——提示用户控制台操作后重试
- 浏览器 wasm MIME：python http.server 本地预览可能缺 `.wasm` MIME；部署侧 nginx 默认 MIME 正确，本地预览仅作参考
- 部署 user-api 容器的 `AccessSecret`/`wallet_token` 配置一致性由其 compose 保证（`game_started` 扣费链路在验证 2 中实测，失败则查服务器容器日志 `docker logs web-console-card-api-1`）
