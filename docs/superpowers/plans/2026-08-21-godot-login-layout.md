# Godot 登录页布局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 card-web 仓库搭建 Godot 4.7 桌面工程，交付纯布局的中文登录页（背景 + 邮箱/密码输入框 + 登录按钮 + 游客一键登录按钮），不接接口、无 GDScript。

**Architecture:** 单场景 `login.tscn`：TextureRect 背景（keep_aspect_covered）→ CenterContainer → VBoxContainer 四控件垂直居中。视觉全部由共享主题 `main_theme.tres`（Noto Sans SC + 古铜金 StyleBox）定义，后续大厅/游戏 UI 复用。

**Tech Stack:** Godot 4.7.2（CLI `/Users/dn/bin/godot`）、Noto Sans SC（OFL）、纯 .tscn/.tres 资源（无脚本）。

**Spec:** `docs/superpowers/specs/2026-08-21-godot-login-layout-design.md`

## Global Constraints

- Godot 4.7.2，CLI 命令为 `godot`（已在 PATH）
- 仓库内**不得出现任何 .gd 脚本**（验证用临时脚本只放 /tmp，不进仓库）
- 渲染器：`gl_compatibility`（桌面 + mobile 同步设置）
- 基础分辨率 1920×1080，stretch `canvas_items` + `expand`；窗口可缩放，min 1280×720
- 配色固定值：底 `#0B120D`、强调 `#B08D4A`、正文 `#E8DCC0`、placeholder `#6B6455`、focus/hover 提亮 `#D4AF6A`
- UI 文案固定：「邮箱」「密码」「登 录」「游客一键登录」（「登 录」中间空格为有意排版）
- 布局规格：四控件统一 420×56、字号 24、VBox separation 24
- 文件路径固定：`assets/login/login_bg.png`、`assets/fonts/NotoSansSC-Regular.ttf`（若下载回退到 OTF 则为 `NotoSansSC-Regular.otf`，主题引用随之调整）、`themes/main_theme.tres`、`scenes/login/login.tscn`
- 本机受限网络，下载走代理 `https_proxy=http://127.0.0.1:7890`
- commit message 用 Conventional Commits（docs/feat/chore/fix）

## File Structure

```
project.godot                     # 工程配置（Task 1 建，Task 4 挂主场景）
.gitignore                        # 忽略 .godot/ 导入缓存与导出产物（Task 1）
assets/login/login_bg.png         # 登录背景（Task 1 由 login/登录背景图.png 移入）
assets/login/login_bg.png.import  # 导入配置：VRAM 压缩 + mipmap（Task 1）
assets/fonts/NotoSansSC-Regular.ttf  # 中文字体 OFL（Task 2）
assets/fonts/LICENSE-NotoSansSC.txt  # OFL 许可文本，随包分发要求（Task 2）
themes/main_theme.tres            # 字体+配色+StyleBox，含 SecondaryButton 类型变体（Task 3）
scenes/login/login.tscn           # 登录场景，无脚本（Task 4）
```

纯布局无单元测试；各任务的"测试环节"为：headless 导入校验、/tmp 临时脚本资源加载校验、运行截图验收。

---

### Task 1: 工程骨架与背景资产

**Files:**
- Create: `project.godot`
- Create: `.gitignore`
- Move: `login/登录背景图.png` → `assets/login/login_bg.png`（文件未跟踪，直接 mv，等价 git mv）
- Generated: `assets/login/login_bg.png.import`（修改两个导入参数）

**Interfaces:**
- Consumes: 无（首任务）
- Produces: `res://assets/login/login_bg.png`（已导入纹理，后续场景 ExtResource 引用）；project.godot 的 stretch/渲染器设置（后续任务依赖）

- [ ] **Step 1: 移动背景图并写工程文件**

```bash
cd /Users/dn/card-web
mkdir -p assets/login assets/fonts themes scenes/login
mv "login/登录背景图.png" assets/login/login_bg.png
rmdir login
```

写 `project.godot`（完整内容）：

```ini
; Engine configuration file.
config_version=5

[application]

config/name="Cthulhu Poker"
config/features=PackedStringArray("4.7")

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/resizable=true
window/size/min_width=1280
window/size/min_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

说明：`mode=windowed` 是默认值，不显式写（该枚举序列化值有歧义，写错反而破坏配置）；spec 的"windowed"要求由默认值满足。

写 `.gitignore`（完整内容）：

```gitignore
.godot/
export/
build/
```

- [ ] **Step 2: 首次导入并改导入参数为 VRAM+mipmap**

```bash
cd /Users/dn/card-web
godot --headless --import 2>&1 | tail -5
```

Expected: 退出码 0，生成 `assets/login/login_bg.png.import` 和 `.godot/imported/` 下的 ctex。

修改生成的 `.import` 文件中 `[params]` 段两行（sed，若无匹配则手工编辑）：

```bash
sed -i '' -e 's|^compress/mode=0|compress/mode=2|' -e 's|^mipmaps/generate=false|mipmaps/generate=true|' assets/login/login_bg.png.import
grep -E '^(compress/mode|mipmaps/generate)' assets/login/login_bg.png.import
```

Expected 输出：
```
compress/mode=2
mipmaps/generate=true
```

（compress/mode：0=Lossless 1=Lossy 2=VRAM Compressed；背景图按 spec 用 VRAM + mipmap。）

- [ ] **Step 3: 重新导入并验证**

```bash
godot --headless --import 2>&1 | tail -5; echo "exit=$?"
ls .godot/imported/ | grep login_bg
```

Expected: `exit=0`；输出包含 `login_bg.png-*.ctex`（VRAM 压缩版本）；无 `ERROR` 行。

- [ ] **Step 4: Commit**

```bash
git add project.godot .gitignore assets/login/
git commit -m "feat: scaffold godot project with background asset"
```

（`login/` 原路径文件从未跟踪过，无需 git rm。）

---

### Task 2: 中文字体（Noto Sans SC + OFL 许可）

**Files:**
- Create: `assets/fonts/NotoSansSC-Regular.ttf`（下载；失败回退 `.otf`）
- Create: `assets/fonts/LICENSE-NotoSansSC.txt`

**Interfaces:**
- Consumes: Task 1 的目录结构与 .gitignore
- Produces: `res://assets/fonts/NotoSansSC-Regular.ttf`（Task 3 主题 ExtResource 引用；若为 OTF 回退，Task 3 中字体路径改为 `res://assets/fonts/NotoSansSC-Regular.otf`）

- [ ] **Step 1: 下载字体（主源：可变字体 TTF，默认字重 400=Regular）**

```bash
cd /Users/dn/card-web
https_proxy=http://127.0.0.1:7890 curl -fL --retry 2 \
  -o assets/fonts/NotoSansSC-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
```

Expected: 下载成功，文件 > 3MB。

- [ ] **Step 2: 若主源失败，用回退源（静态子集 OTF）**

```bash
https_proxy=http://127.0.0.1:7890 curl -fL --retry 2 \
  -o assets/fonts/NotoSansSC-Regular.otf \
  "https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf"
```

Expected: 下载成功。**后续所有引用字体的地方用 `.otf` 路径**（仅 Task 3 主题的 ExtResource path 一处）。

- [ ] **Step 3: 下载 OFL 许可文本**

```bash
https_proxy=http://127.0.0.1:7890 curl -fL --retry 2 \
  -o assets/fonts/LICENSE-NotoSansSC.txt \
  "https://github.com/google/fonts/raw/main/ofl/notosanssc/OFL.txt"
```

- [ ] **Step 4: 校验文件与导入**

```bash
file assets/fonts/NotoSansSC-Regular.* assets/fonts/LICENSE-NotoSansSC.txt
godot --headless --import 2>&1 | tail -3; echo "exit=$?"
```

Expected: 字体文件输出含 `TrueType Font Data` 或 `OpenType`；LICENSE 文件含 `SIL OPEN FONT LICENSE`；import `exit=0` 无 ERROR。

- [ ] **Step 5: Commit**

```bash
git add assets/fonts/
git commit -m "chore: bundle noto sans sc font with ofl license"
```

---

### Task 3: 主题资源 main_theme.tres

**Files:**
- Create: `themes/main_theme.tres`
- Test: `/tmp/check_theme.gd`（临时校验脚本，**不进仓库**）

**Interfaces:**
- Consumes: `res://assets/fonts/NotoSansSC-Regular.ttf`（Task 2）
- Produces: `res://themes/main_theme.tres`——类型变体名 **`SecondaryButton`**（基类型 Button）；主题项：`LineEdit` normal/focus 样式、`Button` normal/hover/pressed 样式、`Button/theme_type_variations`、`default_font_size=24`。Task 4 场景按这些名字引用。

- [ ] **Step 1: 写主题文件（完整内容，字体为 .ttf 版）**

`themes/main_theme.tres`：

```tres
[gd_resource type="Theme" load_steps=10 format=3]

[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSC-Regular.ttf" id="1_font"]

[sub_resource type="StyleBoxFlat" id="LineEdit_normal"]
content_margin_left = 16.0
content_margin_top = 12.0
content_margin_right = 16.0
content_margin_bottom = 12.0
bg_color = Color(0.043137, 0.070588, 0.05098, 0.85)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.690196, 0.552941, 0.290196, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="LineEdit_focus"]
draw_center = false
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.831373, 0.686275, 0.415686, 1)
expand_margin_left = 2.0
expand_margin_top = 2.0
expand_margin_right = 2.0
expand_margin_bottom = 2.0

[sub_resource type="StyleBoxFlat" id="Button_primary_normal"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.105882, 0.137255, 0.105882, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.690196, 0.552941, 0.290196, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="Button_primary_hover"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.137255, 0.176471, 0.137255, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.831373, 0.686275, 0.415686, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="Button_primary_pressed"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.070588, 0.090196, 0.070588, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.54902, 0.435294, 0.207843, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="Button_secondary_normal"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.043137, 0.070588, 0.05098, 0.6)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.419608, 0.392157, 0.333333, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="Button_secondary_hover"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.043137, 0.070588, 0.05098, 0.6)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.603922, 0.560784, 0.47451, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="Button_secondary_pressed"]
content_margin_left = 12.0
content_margin_top = 10.0
content_margin_right = 12.0
content_margin_bottom = 10.0
bg_color = Color(0.043137, 0.070588, 0.05098, 0.6)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.305882, 0.282353, 0.235294, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[resource]
default_font = ExtResource("1_font")
default_font_size = 24
LineEdit/colors/font_color = Color(0.909804, 0.862745, 0.752941, 1)
LineEdit/colors/font_placeholder_color = Color(0.419608, 0.392157, 0.333333, 1)
LineEdit/colors/caret_color = Color(0.831373, 0.686275, 0.415686, 1)
LineEdit/colors/selection_color = Color(0.690196, 0.552941, 0.290196, 0.35)
LineEdit/styles/normal = SubResource("LineEdit_normal")
LineEdit/styles/focus = SubResource("LineEdit_focus")
Button/theme_type_variations = PackedStringArray("SecondaryButton")
Button/colors/font_color = Color(0.909804, 0.862745, 0.752941, 1)
Button/colors/font_hover_color = Color(1, 0.94902, 0.85098, 1)
Button/colors/font_pressed_color = Color(0.74902, 0.658824, 0.45098, 1)
Button/styles/normal = SubResource("Button_primary_normal")
Button/styles/hover = SubResource("Button_primary_hover")
Button/styles/pressed = SubResource("Button_primary_pressed")
SecondaryButton/colors/font_color = Color(0.72, 0.68, 0.58, 1)
SecondaryButton/colors/font_hover_color = Color(0.909804, 0.862745, 0.752941, 1)
SecondaryButton/colors/font_pressed_color = Color(0.54902, 0.517647, 0.439216, 1)
SecondaryButton/styles/normal = SubResource("Button_secondary_normal")
SecondaryButton/styles/hover = SubResource("Button_secondary_hover")
SecondaryButton/styles/pressed = SubResource("Button_secondary_pressed")
```

注 1：若 Task 2 用了 `.otf` 回退，把第 3 行 `path` 改为 `res://assets/fonts/NotoSansSC-Regular.otf`。
注 2（对 spec 的明确偏离）：spec 提到"fallback 链保留 Godot 默认字体兜底"——Godot 4 导出后无系统字体自动回退，fallback 链需打包第二字体才有意义。本页全部文案字符集 Noto Sans SC 全覆盖，暂不打包第二字体；出现生僻字需求时再补。
配色出处：#0B120D/#B08D4A/#E8DCC0/#6B6455/#D4AF6A 的 float 值（÷255）；focus 样式 `draw_center=false` + `expand_margin=2` 使金边画在输入框外侧（LineEdit 的 focus 画在 normal 之下，不外扩会被遮住）。

- [ ] **Step 2: 写临时校验脚本（/tmp，不进仓库）**

`/tmp/check_theme.gd`：

```gdscript
extends SceneTree

func _init():
    var t = load("res://themes/main_theme.tres")
    if t == null:
        push_error("THEME_FAIL: load returned null")
        quit(1)
        return
    var base = t.get_type_variation_base("SecondaryButton")
    var has_focus = t.has_theme_item(Theme.DATA_TYPE_STYLEBOX, "focus", "LineEdit")
    var size = t.default_font_size
    print("THEME_OK base=", base, " lineedit_focus=", has_focus, " font_size=", size)
    quit(0)
```

- [ ] **Step 3: 运行校验**

```bash
cd /Users/dn/card-web
godot --headless --script /tmp/check_theme.gd 2>&1 | grep -E "THEME_OK|THEME_FAIL|ERROR|Parse"
echo "exit=$?"
```

Expected: 输出 `THEME_OK base=Button lineedit_focus=True font_size=24`，无 `THEME_FAIL`/`Parse Error`。
（若报 parse error，多为属性名拼写——逐字核对 SubResource id 与 `[resource]` 段引用。）

- [ ] **Step 4: Commit**

```bash
git add themes/
git commit -m "feat: add main theme with cthulhu bronze palette"
```

---

### Task 4: 登录场景

**Files:**
- Create: `scenes/login/login.tscn`
- Modify: `project.godot`（追加主场景设置）

**Interfaces:**
- Consumes: `res://assets/login/login_bg.png`（Task 1）、`res://themes/main_theme.tres` 与类型变体 `SecondaryButton`（Task 3）
- Produces: 可运行的登录场景；`project.godot` 的 `run/main_scene`（Task 5 验收直接 `godot --path .` 运行）

- [ ] **Step 1: 写场景文件（完整内容）**

`scenes/login/login.tscn`：

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://assets/login/login_bg.png" id="1_bg"]
[ext_resource type="Theme" path="res://themes/main_theme.tres" id="2_theme"]

[node name="Login" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme = ExtResource("2_theme")

[node name="Background" type="TextureRect" parent="."]
texture = ExtResource("1_bg")
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
stretch_mode = 6

[node name="Center" type="CenterContainer" parent="Background"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Background/Center"]
theme_override_constants/separation = 24

[node name="EmailInput" type="LineEdit" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(420, 56)
layout_mode = 2
placeholder_text = "邮箱"

[node name="PasswordInput" type="LineEdit" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(420, 56)
layout_mode = 2
placeholder_text = "密码"
secret = true

[node name="LoginButton" type="Button" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(420, 56)
layout_mode = 2
text = "登 录"

[node name="GuestButton" type="Button" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(420, 56)
layout_mode = 2
theme_type_variation = "SecondaryButton"
text = "游客一键登录"
```

注：`stretch_mode = 6` 即 `keep_aspect_covered`（枚举：…4=keep_aspect, 5=keep_aspect_centered, 6=keep_aspect_covered）。

- [ ] **Step 2: 挂主场景**

`project.godot` 的 `[application]` 段追加一行（放在 `config/features` 之后）：

```ini
run/main_scene="res://scenes/login/login.tscn"
```

- [ ] **Step 3: 运行并截图验证**

```bash
cd /Users/dn/card-web
godot --path . --resolution 1920x1080 >/tmp/login_run.log 2>&1 &
GPID=$!
sleep 6
screencapture -x /tmp/login_1920.png
kill $GPID 2>/dev/null
grep -iE "error|parse" /tmp/login_run.log || echo "NO_ERRORS"
```

Expected: `NO_ERRORS`；`/tmp/login_1920.png` 中背景铺满窗口，四个控件在中央黑框内垂直居中排列，placeholder「邮箱」「密码」中文正常渲染（不出现方框豆腐字）。

用图像工具查看 `/tmp/login_1920.png` 确认：控件同宽对齐、居中、占位文字为中文、按钮文字分别为「登 录」「游客一键登录」、整体呈暗绿金色调。

- [ ] **Step 4: Commit**

```bash
git add scenes/ project.godot
git commit -m "feat: add login scene layout"
```

---

### Task 5: 多尺寸验收与交互冒烟

**Files:**
- Test: 截图 `/tmp/login_*.png`（不进仓库）
- Modify: 仅当验收发现问题时修改 Task 1–4 的文件

**Interfaces:**
- Consumes: Task 4 的可运行场景
- Produces: 无新文件（验收通过即交付完成）

- [ ] **Step 1: 三种窗口尺寸截图**

```bash
cd /Users/dn/card-web
for size in 1920x1080 1280x720 2560x1080; do
  godot --path . --resolution $size >/tmp/login_run_$size.log 2>&1 &
  GPID=$!
  sleep 6
  screencapture -x /tmp/login_$size.png
  kill $GPID 2>/dev/null
  sleep 1
done
ls -la /tmp/login_*.png
```

Expected: 三张截图都满足——UI 整体居中于窗口、四个控件完整可见不裁切不错位、2560x1080 超宽下背景多露出但 UI 仍居中、1280x720 下按比例缩小不变形。

- [ ] **Step 2: 逐张检查截图**

用图像工具查看三张截图，核对：
- VBox 恰好落在背景中央黑色矩形装饰内（略小于黑框、不溢出）
- 两个输入框与两个按钮同宽（420 基准）对齐
- 中文文字清晰无豆腐块

- [ ] **Step 3: 交互冒烟（人工，2 分钟）**

运行 `godot --path .`，操作确认：
- [ ] 邮箱框可点击聚焦，出现金色 focus 边，可输入文字，光标为金色
- [ ] 密码框输入显示圆点
- [ ] 「登 录」按钮 hover 变亮（金边提亮 + 底色变亮），按下变暗
- [ ] 「游客一键登录」hover 边框变浅
- [ ] Tab 键可在四个控件间切换焦点

发现问题：回对应任务文件修复，`fix: ...` 提交；全部通过则本步零改动。

- [ ] **Step 4: 最终状态检查**

```bash
cd /Users/dn/card-web
godot --headless --import 2>&1 | grep -iE "error|warn" || echo "IMPORT_CLEAN"
git status --short
git log --oneline
find . -name "*.gd" -not -path "./.godot/*" | wc -l
```

Expected: `IMPORT_CLEAN`；工作区干净（或仅剩本步未提交的 fix）；提交历史含 Task 1–4 四个 commit；脚本计数为 `0`（纯布局无脚本约束达标）。

---

## 验收对照（spec → 任务）

| spec 验收标准 | 覆盖任务 |
|---|---|
| `godot --headless --import` 通过无错误 | Task 1/2/3 各验证步 + Task 5 Step 4 |
| 三种窗口尺寸截图：居中、不裁切、不错位 | Task 5 Steps 1–2 |
| 输入框聚焦输入 / 密码圆点 / placeholder 中文 / 按钮 hover 反馈 | Task 4 Step 3 + Task 5 Step 3 |
