# Godot 客户端登录页布局设计（card-web 第一版）

- 日期：2026-08-21（同日修订：设计提供的 UI 素材到位，样式从手绘 StyleBoxFlat 改为设计素材）
- 状态：已与用户确认
- 关联：后端 `/Users/dn/user`（go-zero 登录系统，本版不接接口）

## 背景

- `card-web` 是 Cthulhu Poker（克苏鲁主题扑克）的 Godot 客户端仓库。
- 设计师在 `login/` 目录提供了导出素材（Lovart 导出的 SVG 壳，内嵌 base64 PNG 位图）：
  - `2k背景图.svg`（2730×1536，≈16:9，中央黑框为登录 UI 预留区）
  - `web端 SIGN IN 按钮底框.svg`（2019×779，无文字烙印）
  - `web端 Guest Login 按钮底框.svg`（1893×831）
  - `web端输入框通用底框无分隔线.svg`（1983×793）
  - `web端输入框用户图标.svg` / `web端输入框锁图标.svg`（1254×1254）/ `web端输入框眼睛图标.svg`（1650×953）
- 后端 `/Users/dn/user` 提供：注册 / 密码登录 / 游客登录 / 登出 / me（JWT）。本版不接接口。
- 本机已装 Godot 4.7.2（`/Users/dn/bin/godot`）。
- 精确布局（像素位置/尺寸）由用户后续在编辑器手动微调；本版给出合理的初始布局。

## 目标（本版）

做一个**纯布局**的登录页：背景 + 邮箱输入框（用户图标）+ 密码输入框（锁图标 + 眼睛图标）+
登录按钮 + 游客一键登录按钮，全部使用设计素材，中文文案，桌面平台运行。

## 非目标

- 接通后端接口（下一版）
- 眼睛图标的显隐切换交互（需脚本，留给行为版；本版作静态装饰）
- 注册入口、忘记密码
- 大厅 / 游戏内 UI
- Web 导出（桌面先行；工程配置需为 Web 留好路）

## 关键决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 布局方式 | 容器布局（CenterContainer + VBoxContainer） | 不同分辨率 / 窗口比例自适应；后续 Web 导出各种屏幕不错位 |
| 渲染器 | `gl_compatibility` | Web 导出仅支持 Compatibility；桌面 / Web 一套配置，免将来换渲染器回归 |
| 分辨率策略 | 基础分辨率 1920×1080，stretch `canvas_items` + `aspect expand` | UI 等比缩放；宽屏多露背景、不裁 UI、不变形 |
| 素材处理 | 从 SVG 壳抽取内嵌 PNG 导入 Godot | SVG 只是 base64 PNG 包装；抽 PNG 确定性最高，不依赖 SVG 栅格化 |
| 素材目录 | `login/` 保留为设计源文件（入库）；`assets/login/` 放抽取出的游戏内资源 | 设计重导出时有固定落点，游戏资源与源分离 |
| 按钮样式 | SIGN IN / Guest 底框 → StyleBoxTexture 九宫格（左右 margin 拉伸） | 底框无烙印文字，文字由 Godot 绘制中文；宽度变化时端部装饰不变形 |
| 输入框样式 | 通用底框 → StyleBoxTexture；左图标用 TextureRect 子节点（锚 center-left），右图标用 LineEdit `right_icon` | 修订（2026-08-21 实施时发现）：Godot 4 LineEdit 无 `left_icon` 属性（3.x 才有），左图标只能作为控件子节点叠加；文本避让依赖主题 content_margin_left=72 |
| 眼睛图标 | 密码框 `right_icon` 静态装饰 | 显隐切换需脚本，本版无脚本约束；注意三枚图标 PNG 为设计导出、无透明通道（不透明白底），待设计师重导出 |
| 导入设置 | 背景：VRAM 压缩 + mipmap；UI 小图：默认 lossless | 背景省显存；带透明度的小 UI 图 VRAM 压缩会有瑕疵 |
| 中文字体 | 打包 Noto Sans SC（OFL 许可，需下载） | 系统字体许可不可再分发；Godot 默认字体无 CJK 字形 |
| 文件名 | 抽取 PNG 用 ASCII 名（login_bg / input_frame / sign_in_frame / guest_frame / icon_user / icon_lock / icon_eye） | 避免导出 / 工具链对 Unicode 路径的兼容问题 |
| 脚本 | 本版无任何 GDScript | 纯布局，按钮不挂行为 |

## 详细设计

### 目录结构

```
card-web/
├── project.godot            # Godot 4.7.2
├── .gitignore               # .godot/ 导入缓存、构建产物
├── login/                   # 设计源文件（SVG，入库，重导出落点）
├── assets/
│   ├── login/               # 从 SVG 抽取的 PNG（游戏内资源）
│   │   ├── login_bg.png         # 背景 2730×1536 原尺寸
│   │   ├── input_frame.png      # 输入框底框，resampleHeight 96 → 240×96
│   │   ├── sign_in_frame.png    # 登录按钮底框，resampleHeight 96 → 249×96
│   │   ├── guest_frame.png      # 游客按钮底框，resampleHeight 96 → 218×96
│   │   ├── icon_user.png        # 用户图标，48×48
│   │   ├── icon_lock.png        # 锁图标，48×48
│   │   └── icon_eye.png         # 眼睛图标，resampleHeight 32 → 55×32
│   └── fonts/NotoSansSC-Regular.ttf
├── scenes/
│   └── login/login.tscn
└── themes/
    └── main_theme.tres
```

### 工程配置（project.godot）

- `config/features = ["4.7"]`，主场景 `scenes/login/login.tscn`
- `display/window/size/viewport_width = 1920`、`viewport_height = 1080`
- `display/window/size/resizable = true`，`min_width = 1280`、`min_height = 720`（mode 默认即 windowed）
- `display/window/stretch/mode = canvas_items`，`aspect = expand`
- `rendering/renderer/rendering_method = gl_compatibility`（含 `rendering_method.mobile` 同步设置）

### 场景树（scenes/login/login.tscn）

```
Login (Control, full rect)
└── Background (TextureRect, stretch_mode=keep_aspect_covered, full rect)
    └── CenterContainer (full rect)
        └── VBoxContainer (居中, separation 24)
            ├── EmailInput     LineEdit  placeholder「邮箱」, left_icon=icon_user
            ├── PasswordInput  LineEdit  placeholder「密码」, secret=true,
            │                           left_icon=icon_lock, right_icon=icon_eye
            ├── LoginButton    Button    「登 录」      底框 sign_in_frame
            └── GuestButton    Button    「游客一键登录」底框 guest_frame
```

布局初始规格（基础分辨率下，用户后续手动微调）：

- 四个控件统一宽 440px、高 96px，字号 28，VBox separation 24
- 底框高度即控件高度，九宫格只在水平方向拉伸（左右 texture_margin：输入框 48、登录框 80、游客框 80）
- VBox 通过 CenterContainer 落在背景图中央黑框内（黑框是背景图的一部分，不单独绘制）

### 主题（themes/main_theme.tres）

- 默认字体 Noto Sans SC，默认字号 28
- 配色（对齐设计素材的古铜金调）：
  - 正文 `#E8DCC0`（米金）
  - placeholder `#6B6455`（暗沙）
  - caret / focus 提亮 `#D4AF6A`
- LineEdit：normal = StyleBoxTexture(input_frame)（左 margin 48，content_margin_left 72 给图标让位）；
  focus = StyleBoxFlat 金色外圈（draw_center=false + expand_margin 2）
- Button（主，登录）：normal/hover/pressed = StyleBoxTexture(sign_in_frame)，
  hover `modulate_color` 提亮、pressed 压暗
- SecondaryButton（类型变体，游客）：normal/hover/pressed = StyleBoxTexture(guest_frame)，同样调制
- 主题挂场景根节点，后续大厅 / 游戏 UI 复用

### 错误处理

纯布局无运行时错误路径。字体说明：Godot 4 导出后无系统字体自动回退，本页文案字符集
Noto Sans SC 全覆盖，不打包第二字体；出现生僻字需求时再补。

## 验收标准

- [ ] `godot --headless --import` 通过，无资源导入错误
- [ ] 实际运行截图检查三种窗口尺寸：1920×1080、1280×720、2560×1080（超宽）——UI 居中、不裁切、不错位
- [ ] 交互冒烟：输入框可聚焦可输入；密码框显示圆点；placeholder 中文正常渲染；两个按钮 hover 有视觉反馈
- [ ] 素材完整性：背景 / 两个按钮底框 / 输入框底框 / 三枚图标全部正确显示，无拉伸变形（端部装饰不糊不歪）

## 后续版本预留（不在本版范围）

- 接口层：HTTPRequest 封装、JWT 持久化（桌面 `user://`）
- 眼睛图标显隐切换（约 6 行脚本）
- 注册入口（后端 `POST /api/v1/auth/register` 已就绪）
- Web 导出（浏览器侧 CORS 需后端加中间件）
