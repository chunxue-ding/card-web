# Web 打包与云服务器部署 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本地 CLI 打出 Godot Web 包并部署到 `120.27.241.134:8080`（nginx 同源反代到已运行的两个后端容器），公网浏览器可玩到 `game_started`。

**Architecture:** 唯一代码改动是 AppConfig 的 web 同源适配（`OS.has_feature("web")` → `JavaScriptBridge.eval("location.origin")`）；其余为构建与运维：模板安装 → export_presets → headless 导出 → rsync 上传 → 新增 nginx server 块（不动 web-console）→ 公网验证。spec：`docs/superpowers/specs/2026-08-22-web-export-deploy-design.md`。

**Tech Stack:** Godot 4.7.2 headless export、nginx 1.30.4、rsync/ssh（密钥已配好：`root@120.27.241.134`）。

## Global Constraints

- 本地命令都在 `/Users/dn/card-web`；Godot 二进制 `/Users/dn/bin/godot`。
- 服务器：`root@120.27.241.134`（密钥登录可用，勿再使用密码）；后端容器 `web-console-user-api-1`(:8888)/`web-console-card-api-1`(:8890) 已在跑，**不得改动或重启后端容器与 80 端口 web-console 站点**。
- nginx 新配置只新增 `/etc/nginx/conf.d/card-web.conf`；改完必须 `nginx -t` 通过再 `nginx -s reload`。
- GDScript tab 缩进；Conventional Commits（可 `--no-verify`）。
- 网络受限：外网下载经代理 `HTTPS_PROXY=http://127.0.0.1:7890`。
- 导出产物 `export/web/`（已 gitignore，不入库）；`export_presets.cfg` 入库。
- **安全组放行 8080 需用户在阿里云控制台操作**——公网 curl 验证前先提醒用户，服务器本机 firewalld 若启用需放行。
- 修改 `scripts/config/app_config.gd` 前先 `git status`，发现他人未提交改动报 BLOCKED。

---

### Task 1: AppConfig web 同源适配

**Files:**
- Create: `tests/test_app_config.gd`
- Modify: `scripts/config/app_config.gd`（全文替换）

**Interfaces:**
- Consumes: 无
- Produces: `AppConfig.get_base_url()/get_card_base_url()` 行为——env 覆盖最优先；`OS.has_feature("web")` 时返回 `str(JavaScriptBridge.eval("location.origin"))`；否则默认 `http://127.0.0.1:8888` / `:8890`（Task 3 导出的包依赖此行为）

- [ ] **Step 0: 并行编辑检查**

Run: `git status --short` —— `scripts/config/app_config.gd` 有他人未提交改动则报 BLOCKED。

- [ ] **Step 1: 写测试（native 分支可测；web 分支留给部署验证）**

创建 `tests/test_app_config.gd`：

```gdscript
extends SceneTree
## AppConfig 行为单测：env 覆盖优先；native 无 env 时用默认值
## （web 同源分支依赖浏览器环境，由部署后的 /browse 验证覆盖）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_app_config.gd

const Helper = preload("res://tests/test_helper.gd")
const AppConfig = preload("res://scripts/config/app_config.gd")

var h := Helper.new()


func _initialize() -> void:
	OS.set_environment("CARD_API_URL", "http://override.test:9000")
	OS.set_environment("CARD_CARD_URL", "http://card-override.test:9001")
	h.check(AppConfig.get_base_url() == "http://override.test:9000", "CARD_API_URL 覆盖生效")
	h.check(AppConfig.get_card_base_url() == "http://card-override.test:9001", "CARD_CARD_URL 覆盖生效")
	OS.set_environment("CARD_API_URL", "")
	OS.set_environment("CARD_CARD_URL", "")
	h.check(AppConfig.get_base_url() == "http://127.0.0.1:8888", "无 env 时 user 默认地址")
	h.check(AppConfig.get_card_base_url() == "http://127.0.0.1:8890", "无 env 时 card 默认地址")
	h.finish(self)
```

先运行确认前两项 PASS、后两项 FAIL（当前无 env 时也返回默认——应已 PASS；若 4 项全 PASS 说明默认分支未破坏，测试仍有效锁定行为，继续）：`/Users/dn/bin/godot --headless --script res://tests/test_app_config.gd`

- [ ] **Step 2: 实现**

`scripts/config/app_config.gd` 全文替换为：

```gdscript
class_name AppConfig
## 环境配置：API base URL 解析。
## 优先级：环境变量覆盖（原生调试用）→ web 导出取页面 origin（同源反代）→ 默认本机后端。

const DEFAULT_BASE_URL := "http://127.0.0.1:8888"
const DEFAULT_CARD_BASE_URL := "http://127.0.0.1:8890"


static func get_base_url() -> String:
	var from_env := OS.get_environment("CARD_API_URL")
	if from_env != "":
		return from_env
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin"))
	return DEFAULT_BASE_URL


static func get_card_base_url() -> String:
	var from_env := OS.get_environment("CARD_CARD_URL")
	if from_env != "":
		return from_env
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin"))
	return DEFAULT_CARD_BASE_URL
```

- [ ] **Step 3: 运行测试确认通过 + 回归**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_app_config.gd && /Users/dn/bin/godot --headless --script res://tests/test_card_contract.gd && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: 4/4、20/20、39/39 全 0 failed。

- [ ] **Step 4: 提交**

```bash
git add tests/test_app_config.gd scripts/config/app_config.gd
git commit -m "feat: resolve api base url from page origin in web exports" --no-verify
```

---

### Task 2: 安装 Godot 导出模板（一次性）

**Files:**
- Create: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`（模板文件，不入库）

- [ ] **Step 1: 检查现状**

Run: `ls "$HOME/Library/Application Support/Godot/export_templates/" 2>/dev/null || echo "目录不存在"`
Expected: 输出空或不存在（此前确认无模板）。

- [ ] **Step 2: 经代理下载模板包**

Run:
```bash
cd /tmp && HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 curl -L --fail -o godot-templates.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz && ls -lh godot-templates.tpz
```
Expected: 下载完成，文件数百 MB。若超时/失败重试一次；仍失败报 BLOCKED 并在报告写明（给手动指引：编辑器里 Editor→Manage Export Templates 下载）。

- [ ] **Step 3: 解压安装**

Run:
```bash
unzip -o -q /tmp/godot-templates.tpz -d /tmp/godot-templates
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
cp /tmp/godot-templates/templates/* "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/"
ls "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/" | head -8
```
Expected: 列出 `web_release.zip`、`web_dlink_release.zip`、`macos.zip`、`linux_release.x86_64` 等模板文件（web 系列必须存在）。

- [ ] **Step 4: 清理下载物**

Run: `rm -rf /tmp/godot-templates /tmp/godot-templates.tpz && echo cleaned`
Expected: `cleaned`。

---

### Task 3: 导出预设与首次打包

**Files:**
- Create: `export_presets.cfg`（入库）
- 产物: `export/web/`（不入库）

**Interfaces:**
- Consumes: 模板（Task 2）、AppConfig 同源适配（Task 1）
- Produces: `export/web/index.html` + `.wasm` + `.js` + `.png`（Task 4 部署物）；命令 `/Users/dn/bin/godot --headless --export-release "Web"` 可重复执行

- [ ] **Step 1: 写 export_presets.cfg**

创建 `export_presets.cfg`：

```ini
[preset.0]

name="Web"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="export/web/index.html"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extension_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
```

- [ ] **Step 2: 导出**

Run: `cd /Users/dn/card-web && /Users/dn/bin/godot --headless --export-release "Web" 2>&1 | tail -5 && ls -la export/web/`
Expected: 无 ERROR；`export/web/` 含 `index.html`、`index.wasm`、`index.js`（可能还有 `index.png`、`index.audio.worklet.js`）。若报缺模板/签名错误，检查 Task 2 安装路径是否精确为 `4.7.2.stable`。

- [ ] **Step 3: 客户端回归（导出过程不破坏工程）**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd 2>&1 | tail -1`
Expected: `== 39 passed, 0 failed ==`。

- [ ] **Step 4: 提交预设**

```bash
git add export_presets.cfg
git commit -m "build: add web export preset with no-thread variant" --no-verify
```

---

### Task 4: 服务器部署（上传 + nginx :8080 + reload）

**Files:**
- 服务器新增: `/etc/nginx/conf.d/card-web.conf`、`/var/www/card-web/`（导出产物）

**Interfaces:**
- Consumes: `export/web/`（Task 3）、服务器 ssh 密钥访问、已运行的后端容器（127.0.0.1:8888/8890）
- Produces: `http://120.27.241.134:8080/` 静态站 + `/api/v1/*` 同源反代（Task 5 验证）

- [ ] **Step 1: 上传产物**

Run:
```bash
ssh root@120.27.241.134 'mkdir -p /var/www/card-web'
rsync -a --delete /Users/dn/card-web/export/web/ root@120.27.241.134:/var/www/card-web/
ssh root@120.27.241.134 'ls /var/www/card-web/'
```
Expected: 远端列出 `index.html`、`index.wasm`、`index.js` 等。

- [ ] **Step 2: 写 nginx 配置并生效**

Run:
```bash
ssh root@120.27.241.134 'cat > /etc/nginx/conf.d/card-web.conf << "EOF"
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
EOF
nginx -t && nginx -s reload && echo RELOADED'
```
Expected: `nginx: configuration file ... test is successful` + `RELOADED`。

- [ ] **Step 3: 服务器本机验证 + 防火墙**

Run:
```bash
ssh root@120.27.241.134 'curl -s -o /dev/null -w "page:%{http_code}\n" localhost:8080/; curl -s localhost:8080/api/v1/healthz; echo; systemctl is-active firewalld 2>/dev/null || echo firewalld-inactive'
```
Expected: `page:200`；`{"code":0,"message":"ok"}`；firewalld inactive（若 active 则执行 `firewall-cmd --permanent --add-port=8080/tcp && firewall-cmd --reload`）。

- [ ] **Step 4: 提醒用户放行安全组**

在报告与回复中明确：**阿里云控制台 → 安全组 → 入方向放行 TCP 8080**（工具不可达，必须人工）。放行前公网验证（Task 5）会超时。

---

### Task 5: 公网验证（curl + live smoke + 浏览器）

**Files:** 无新增（验证任务）

**Interfaces:**
- Consumes: 部署产物（Task 4）、`tests/live_smoke_room.gd`、`/browse`（主会话技能，浏览器步骤由 controller 执行）

- [ ] **Step 1: 公网 curl**

Run: `curl -s -o /dev/null -w "page:%{http_code}\n" --max-time 8 http://120.27.241.134:8080/ && curl -s --max-time 8 http://120.27.241.134:8080/api/v1/healthz`
Expected: `page:200` + `{"code":0,"message":"ok"}`。超时 → 安全组未放行，提醒用户后重试。

- [ ] **Step 2: 公网 live smoke**

Run:
```bash
cd /Users/dn/card-web
CARD_API_URL=http://120.27.241.134:8080 CARD_CARD_URL=http://120.27.241.134:8080 /Users/dn/bin/godot --headless --script res://tests/live_smoke_room.gd 2>&1 | tail -10
```
Expected: 7/7 PASS（注册→建房→WS 经 nginx upgrade→准备→开局扣费→game_started→join 404，全公网链路）。注意 guest 限流按公网 IP：本 smoke 不用 guest，可重复跑；若 `game_started` 失败查 `ssh root@120.27.241.134 'docker logs --tail 50 web-console-card-api-1'`。

- [ ] **Step 3: 浏览器实测（controller 用 /browse 执行）**

主会话用 `/browse` 打开 `http://120.27.241.134:8080`，验证：
1. Godot canvas 渲染出登录页（1920x1080 自适应）
2. 游客登录 → 进主页（昵称/余额显示）
3. 好友同玩 → 创建房间 → 房间页显示房间号与 1 玩家
4. 控制台无 CORS/wasm 加载错误
（此步骤为人工/主会话技能步骤，子代理标记跳过即可。）

- [ ] **Step 4: 收尾提交（如有遗留）**

若验证过程中改了本地文件（不应有），提交；否则无提交。在报告中给出：部署 URL、重打包+重部署的两条命令（`--export-release "Web"` + Task 4 Step 1 的 rsync）、后端容器日志查看命令。
