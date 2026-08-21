# Godot 登录页布局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 card-web 仓库搭建 Godot 4.7 桌面工程，用设计师提供的素材交付纯布局的中文登录页（背景 + 带图标的邮箱/密码输入框 + 登录按钮 + 游客一键登录按钮），不接接口、无 GDScript。

**Architecture:** `login/` 为设计源 SVG（入库）；脚本抽取 SVG 内嵌 PNG 到 `assets/login/` 并降采样为游戏尺寸。单场景 `login.tscn`：TextureRect 背景 → CenterContainer → VBox 四控件。按钮/输入框样式 = 设计底框 StyleBoxTexture 九宫格；图标 = LineEdit `left_icon`/`right_icon`；字体与颜色在共享主题 `main_theme.tres`。

**Tech Stack:** Godot 4.7.2（CLI `godot`）、python3+sips（素材处理）、Noto Sans SC（OFL）、纯 .tscn/.tres（无脚本）。

**Spec:** `docs/superpowers/specs/2026-08-21-godot-login-layout-design.md`（2026-08-21 修订版，素材驱动）

## Global Constraints

- Godot 4.7.2，CLI 命令为 `godot`（已在 PATH）
- 仓库内**不得出现任何 .gd 脚本**（验证用临时脚本只放 /tmp，不进仓库）
- `login/` 目录是设计源文件，**保持原样入库**，不改名不移动
- 渲染器：`gl_compatibility`（桌面 + mobile 同步设置）
- 基础分辨率 1920×1080，stretch `canvas_items` + `expand`；窗口可缩放，min 1280×720
- 控件规格：四控件 440×96、字号 28、VBox separation 24（初始值，用户后续手动微调）
- 配色固定值：正文 `#E8DCC0`、placeholder `#6B6455`、caret/focus `#D4AF6A`
- UI 文案固定：「邮箱」「密码」「登 录」「游客一键登录」（「登 录」中间空格为有意排版）
- 文件路径固定：`assets/login/{login_bg,input_frame,sign_in_frame,guest_frame,icon_user,icon_lock,icon_eye}.png`、`assets/fonts/NotoSansSC-Regular.ttf`（回退 `.otf` 时主题引用随之改）、`themes/main_theme.tres`、`scenes/login/login.tscn`
- 素材导入：`login_bg.png` 用 VRAM 压缩 + mipmap；其余 UI 小图保持默认 lossless（透明图 VRAM 有瑕疵）
- 本机受限网络，下载走代理 `https_proxy=http://127.0.0.1:7890`
- commit message 用 Conventional Commits（docs/feat/chore/fix）

## File Structure

```
project.godot                     # 工程配置（Task 1 建，Task 4 挂主场景）
.gitignore                        # 忽略 .godot/ 导入缓存与导出产物（Task 1）
login/*.svg                       # 设计源文件，7 个，原样入库（Task 1 commit）
assets/login/login_bg.png         # 背景 2730×1536 原尺寸抽取（Task 1）
assets/login/input_frame.png      # 输入框底框 → resampleHeight 96（Task 1）
assets/login/sign_in_frame.png    # 登录按钮底框 → resampleHeight 96（Task 1）
assets/login/guest_frame.png      # 游客按钮底框 → resampleHeight 96（Task 1）
assets/login/icon_user.png        # 用户图标 → 48×48（Task 1）
assets/login/icon_lock.png        # 锁图标 → 48×48（Task 1）
assets/login/icon_eye.png         # 眼睛图标 → resampleHeight 32（Task 1）
assets/fonts/NotoSansSC-Regular.ttf  # 中文字体 OFL（Task 2）
assets/fonts/LICENSE-NotoSansSC.txt  # OFL 许可文本（Task 2）
themes/main_theme.tres            # 字体+颜色+底框 StyleBoxTexture（Task 3）
scenes/login/login.tscn           # 登录场景，无脚本（Task 4）
```

纯布局无单元测试；各任务的"测试环节"为：headless 导入校验、/tmp 临时脚本资源加载校验、运行截图验收。

---

### Task 1: 工程骨架与素材抽取

**Files:**
- Create: `project.godot`
- Create: `.gitignore`
- Create: `assets/login/*.png`（7 个，从 `login/*.svg` 抽取内嵌 PNG 并降采样）
- Generated: `assets/login/login_bg.png.import`（改两个导入参数；UI 小图 .import 不改）

**Interfaces:**
- Consumes: 无（首任务）
- Produces: `res://assets/login/login_bg.png`（背景纹理，Task 4 场景引用）；`res://assets/login/{input_frame,sign_in_frame,guest_frame,icon_user,icon_lock,icon_eye}.png`（Task 3 主题 / Task 4 场景引用）；project.godot 的 stretch/渲染器设置

- [ ] **Step 1: 建目录并写工程文件**

```bash
cd /Users/dn/card-web
mkdir -p assets/login assets/fonts themes scenes/login
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

- [ ] **Step 2: 从 SVG 抽取内嵌 PNG**

```bash
cd /Users/dn/card-web
python3 - <<'EOF'
import re, base64, pathlib
mapping = {
    "2k背景图.svg": "login_bg.png",
    "web端输入框通用底框无分隔线.svg": "input_frame.png",
    "web端 SIGN IN 按钮底框.svg": "sign_in_frame.png",
    "web端 Guest Login 按钮底框.svg": "guest_frame.png",
    "web端输入框用户图标.svg": "icon_user.png",
    "web端输入框锁图标.svg": "icon_lock.png",
    "web端输入框眼睛图标.svg": "icon_eye.png",
}
for src, dst in mapping.items():
    s = pathlib.Path("login") / src
    text = s.read_text()
    m = re.search(r'href="data:image/png;base64,([^"]+)"', text)
    assert m, f"no embedded png found in {src}"
    out = pathlib.Path("assets/login") / dst
    out.write_bytes(base64.b64decode(m.group(1)))
    print("extracted", dst, out.stat().st_size, "bytes")
EOF
```

Expected: 打印 7 行 `extracted ...`，各文件 > 1MB；`ls assets/login/ | wc -l` 为 7。

- [ ] **Step 3: UI 小图降采样（背景保持原尺寸）**

LineEdit 的 icon 按纹理原始像素绘制、不缩放，底框纹理过大也会压垮控件，必须降到游戏尺寸：

```bash
sips --resampleHeight 96 assets/login/input_frame.png assets/login/sign_in_frame.png assets/login/guest_frame.png
sips --resampleHeight 48 assets/login/icon_user.png assets/login/icon_lock.png
sips --resampleHeight 32 assets/login/icon_eye.png
sips -g pixelWidth -g pixelHeight assets/login/*.png
```

Expected（宽高比换算，±2px 正常）：
- login_bg.png 2730×1536（未动）
- input_frame.png ≈240×96、sign_in_frame.png ≈249×96、guest_frame.png ≈219×96
- icon_user.png / icon_lock.png 48×48
- icon_eye.png ≈55×32

- [ ] **Step 4: 首次导入、背景改 VRAM+mipmap、复导**

```bash
godot --headless --import 2>&1 | tail -3
sed -i '' -e 's|^compress/mode=0|compress/mode=2|' -e 's|^mipmaps/generate=false|mipmaps/generate=true|' assets/login/login_bg.png.import
grep -E '^(compress/mode|mipmaps/generate)' assets/login/login_bg.png.import
godot --headless --import 2>&1 | tail -3; echo "exit=$?"
ls .godot/imported/ | grep login_bg
```

Expected: grep 输出 `compress/mode=2` 与 `mipmaps/generate=true`；最终 import `exit=0` 无 ERROR；`.godot/imported/` 出现 `login_bg.png-*.ctex`。（compress/mode：0=Lossless 1=Lossy 2=VRAM；UI 小图的 .import 保持默认不动。）

- [ ] **Step 5: Commit**

```bash
git add project.godot .gitignore login/ assets/login/
git commit -m "feat: scaffold godot project with extracted ui assets"
```

（`login/` 的 SVG 源文件与 `assets/` 抽取产物一并入库；`.godot/` 已被 ignore。）

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
- Consumes: `res://assets/fonts/NotoSansSC-Regular.ttf`（Task 2）、`res://assets/login/{input_frame,sign_in_frame,guest_frame}.png`（Task 1）
- Produces: `res://themes/main_theme.tres`——类型变体名 **`SecondaryButton`**（基类型 Button）；主题项：`LineEdit` normal/focus 样式、`Button` normal/hover/pressed 样式、`Button/theme_type_variations`、`default_font_size=28`。Task 4 场景按这些名字引用。

- [ ] **Step 1: 写主题文件（完整内容，字体为 .ttf 版）**

`themes/main_theme.tres`：

```tres
[gd_resource type="Theme" load_steps=13 format=3]

[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSC-Regular.ttf" id="1_font"]
[ext_resource type="Texture2D" path="res://assets/login/input_frame.png" id="2_input_frame"]
[ext_resource type="Texture2D" path="res://assets/login/sign_in_frame.png" id="3_sign_in_frame"]
[ext_resource type="Texture2D" path="res://assets/login/guest_frame.png" id="4_guest_frame"]

[sub_resource type="StyleBoxTexture" id="LineEdit_normal"]
texture = ExtResource("2_input_frame")
texture_margin_left = 48.0
texture_margin_top = 0.0
texture_margin_right = 48.0
texture_margin_bottom = 0.0
content_margin_left = 72.0
content_margin_top = 8.0
content_margin_right = 16.0
content_margin_bottom = 8.0

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

[sub_resource type="StyleBoxTexture" id="Button_primary_normal"]
texture = ExtResource("3_sign_in_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0

[sub_resource type="StyleBoxTexture" id="Button_primary_hover"]
texture = ExtResource("3_sign_in_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0
modulate_color = Color(1.2, 1.12, 0.95, 1)

[sub_resource type="StyleBoxTexture" id="Button_primary_pressed"]
texture = ExtResource("3_sign_in_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0
modulate_color = Color(0.75, 0.7, 0.6, 1)

[sub_resource type="StyleBoxTexture" id="Button_secondary_normal"]
texture = ExtResource("4_guest_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0

[sub_resource type="StyleBoxTexture" id="Button_secondary_hover"]
texture = ExtResource("4_guest_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0
modulate_color = Color(1.2, 1.12, 0.95, 1)

[sub_resource type="StyleBoxTexture" id="Button_secondary_pressed"]
texture = ExtResource("4_guest_frame")
texture_margin_left = 80.0
texture_margin_top = 0.0
texture_margin_right = 80.0
texture_margin_bottom = 0.0
content_margin_left = 96.0
content_margin_top = 8.0
content_margin_right = 96.0
content_margin_bottom = 8.0
modulate_color = Color(0.75, 0.7, 0.6, 1)

[resource]
default_font = ExtResource("1_font")
default_font_size = 28
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
SecondaryButton/colors/font_color = Color(0.909804, 0.862745, 0.752941, 1)
SecondaryButton/colors/font_hover_color = Color(1, 0.94902, 0.85098, 1)
SecondaryButton/colors/font_pressed_color = Color(0.74902, 0.658824, 0.45098, 1)
SecondaryButton/styles/normal = SubResource("Button_secondary_normal")
SecondaryButton/styles/hover = SubResource("Button_secondary_hover")
SecondaryButton/styles/pressed = SubResource("Button_secondary_pressed")
```

注 1：若 Task 2 用了 `.otf` 回退，把第 3 行 `path` 改为 `res://assets/fonts/NotoSansSC-Regular.otf`。
注 2（对 spec 的明确偏离）：spec 早期版本提过"fallback 链兜底"——Godot 4 导出后无系统字体自动回退，fallback 链需打包第二字体才有意义。本页全部文案字符集 Noto Sans SC 全覆盖，暂不打包第二字体；出现生僻字需求时再补（已写入修订版 spec 错误处理节）。
注 3：`texture_margin` 只设左右——底框端部装饰在左右两端，水平九宫格拉伸；控件高度=纹理高度（96），垂直不拉伸。输入框 `content_margin_left=72` 给 48px 图标让位。配色出处：#E8DCC0/#6B6455/#D4AF6A 的 float 值（÷255）。

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
    var normal: StyleBoxTexture = t.get_stylebox("normal", "Button")
    var size = t.default_font_size
    print("THEME_OK base=", base, " lineedit_focus=", has_focus,
        " button_texture=", normal.texture.resource_path, " font_size=", size)
    quit(0)
```

- [ ] **Step 3: 运行校验**

```bash
cd /Users/dn/card-web
godot --headless --script /tmp/check_theme.gd 2>&1 | grep -E "THEME_OK|THEME_FAIL|ERROR|Parse"
echo "exit=$?"
```

Expected: 输出 `THEME_OK base=Button lineedit_focus=True button_texture=res://assets/login/sign_in_frame.png font_size=28`，无 `THEME_FAIL`/`Parse Error`。
（若报 parse error，多为属性名拼写——逐字核对 SubResource id 与 `[resource]` 段引用。）

- [ ] **Step 4: Commit**

```bash
git add themes/
git commit -m "feat: add main theme styled with design frame assets"
```

---

### Task 4: 登录场景

**Files:**
- Create: `scenes/login/login.tscn`
- Modify: `project.godot`（追加主场景设置）

**Interfaces:**
- Consumes: `res://assets/login/login_bg.png` + `icon_user/icon_lock/icon_eye.png`（Task 1）、`res://themes/main_theme.tres` 与类型变体 `SecondaryButton`（Task 3）
- Produces: 可运行的登录场景；`project.godot` 的 `run/main_scene`（Task 5 验收直接 `godot --path .` 运行）

- [ ] **Step 1: 写场景文件（完整内容）**

`scenes/login/login.tscn`：

```tscn
[gd_scene load_steps=6 format=3]

[ext_resource type="Texture2D" path="res://assets/login/login_bg.png" id="1_bg"]
[ext_resource type="Theme" path="res://themes/main_theme.tres" id="2_theme"]
[ext_resource type="Texture2D" path="res://assets/login/icon_user.png" id="3_iu"]
[ext_resource type="Texture2D" path="res://assets/login/icon_lock.png" id="4_il"]
[ext_resource type="Texture2D" path="res://assets/login/icon_eye.png" id="5_ie"]

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
custom_minimum_size = Vector2(440, 96)
layout_mode = 2
left_icon = ExtResource("3_iu")
placeholder_text = "邮箱"

[node name="PasswordInput" type="LineEdit" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(440, 96)
layout_mode = 2
left_icon = ExtResource("4_il")
right_icon = ExtResource("5_ie")
placeholder_text = "密码"
secret = true

[node name="LoginButton" type="Button" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(440, 96)
layout_mode = 2
text = "登 录"

[node name="GuestButton" type="Button" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(440, 96)
layout_mode = 2
theme_type_variation = "SecondaryButton"
text = "游客一键登录"
```

注：`stretch_mode = 6` 即 `keep_aspect_covered`（枚举：…4=keep_aspect, 5=keep_aspect_centered, 6=keep_aspect_covered）；`left_icon`/`right_icon` 为 LineEdit 原生属性，引擎自动为图标让出文本区。

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

Expected: `NO_ERRORS`；用图像工具查看 `/tmp/login_1920.png` 确认——背景铺满窗口；四个控件在中央黑框内垂直居中、同宽对齐；邮箱框左侧用户图标、密码框左侧锁图标右侧眼睛图标（均不变形）；placeholder「邮箱」「密码」中文正常渲染（无豆腐块）；两个按钮呈设计底框样式，文字分别为「登 录」「游客一键登录」。

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

Expected: 三张截图都满足——UI 整体居中于窗口、四个控件完整可见不裁切不错位、2560x1080 超宽下背景多露出但 UI 仍居中、1280x720 下按比例缩小不变形、按钮端部装饰在任何宽度下不糊不歪（九宫格只拉伸中段）。

- [ ] **Step 2: 逐张检查截图**

用图像工具查看三张截图，核对：
- VBox 恰好落在背景中央黑色矩形装饰内（不溢出）
- 两个输入框与两个按钮同宽（440 基准）对齐，图标位置正确且不变形
- 中文文字清晰无豆腐块

- [ ] **Step 3: 交互冒烟（人工，2 分钟）**

运行 `godot --path .`，操作确认：
- [ ] 邮箱框可点击聚焦，出现金色 focus 外圈，可输入文字，光标为金色
- [ ] 密码框输入显示圆点，眼睛图标显示在右侧
- [ ] 「登 录」按钮 hover 底框提亮，按下压暗
- [ ] 「游客一键登录」按钮 hover 同样有明暗变化
- [ ] Tab 键可在四个控件间切换焦点

发现问题：回对应任务文件修复，`fix: ...` 提交；全部通过则本步零改动。（像素级布局不满意不算问题——用户会自己在编辑器里微调。）

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
| 素材完整显示不变形（背景/底框/图标） | Task 1 Step 3 校验 + Task 4 Step 3 + Task 5 Steps 1–2 |
