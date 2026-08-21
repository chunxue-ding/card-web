# Godot 客户端登录页布局设计（card-web 第一版）

- 日期：2026-08-21
- 状态：已与用户确认
- 关联：后端 `/Users/dn/user`（go-zero 登录系统，本版不接接口）

## 背景

- `card-web` 是 Cthulhu Poker（克苏鲁主题扑克）的 Godot 客户端仓库。当前仓库仅有一张登录背景图
  （`login/登录背景图.png`，5458×3074，约 16:9；画面中央黑色矩形为登录 UI 预留区）。
- 后端 `/Users/dn/user` 提供：注册 / 密码登录 / 游客登录（device_id 绑定）/ 登出 / me（JWT）。
  钱包 batch-debit/credit 为服务间接口，客户端不使用。
- 本机已装 Godot 4.7.2（`/Users/dn/bin/godot`）。

## 目标（本版）

做一个**纯布局**的登录页：背景图 + 邮箱输入框 + 密码输入框 + 登录按钮 + 游客一键登录按钮，
中文文案，桌面平台运行。

## 非目标

- 接通后端接口（下一版）
- 注册入口、忘记密码（布局未包含）
- 大厅 / 游戏内 UI
- Web 导出（桌面先行；工程配置需为 Web 留好路）

## 关键决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 布局方式 | 容器布局（CenterContainer + VBoxContainer） | 不同分辨率 / 窗口比例自适应；后续 Web 导出各种屏幕不错位 |
| 渲染器 | `gl_compatibility` | Web 导出仅支持 Compatibility；桌面 / Web 一套配置，免将来换渲染器回归 |
| 分辨率策略 | 基础分辨率 1920×1080，stretch `canvas_items` + `aspect expand` | UI 等比缩放；宽屏多露背景、不裁 UI、不变形 |
| 中文字体 | 打包 Noto Sans SC（OFL 许可，需下载） | 系统字体（Hiragino / STHeiti）许可不可再分发；Godot 默认字体无 CJK 字形 |
| 背景图路径 | `git mv login/登录背景图.png assets/login/login_bg.png` | ASCII 文件名，避免导出 / 工具链对 Unicode 路径的兼容问题；不留双份 |
| 脚本 | 本版无任何 GDScript | 纯布局，按钮不挂行为 |

## 详细设计

### 目录结构

```
card-web/
├── project.godot            # Godot 4.7.2
├── .gitignore               # .godot/ 导入缓存、构建产物
├── assets/
│   ├── login/login_bg.png   # 由 login/登录背景图.png 移入
│   └── fonts/NotoSansSC-Regular.ttf
├── scenes/
│   └── login/login.tscn
└── themes/
    └── main_theme.tres
```

### 工程配置（project.godot）

- `config/features = ["4.7"]`，主场景 `scenes/login/login.tscn`
- `display/window/size/viewport_width = 1920`、`viewport_height = 1080`
- `display/window/size/mode = windowed`，`resizable = true`，`min_width = 1280`、`min_height = 720`
- `display/window/stretch/mode = canvas_items`，`aspect = expand`
- `rendering/renderer/rendering_method = gl_compatibility`（含 `rendering_method.mobile` 同步设为 gl_compatibility）

### 场景树（scenes/login/login.tscn）

```
Login (Control, full rect)
└── Background (TextureRect, stretch_mode=keep_aspect_covered, full rect)
    └── CenterContainer (full rect)
        └── VBoxContainer (居中, separation 24)
            ├── EmailInput     LineEdit  placeholder「邮箱」
            ├── PasswordInput  LineEdit  placeholder「密码」, secret=true
            ├── LoginButton    Button    「登 录」      主样式（古铜金边）
            └── GuestButton    Button    「游客一键登录」次样式（低调暗边）
```

布局规格（基础分辨率下）：

- 四个控件统一宽 420px、高 56px，字号 24，VBox 内同宽对齐
- VBox 通过 CenterContainer 落在背景图中央黑框内（黑框是背景图的一部分，不单独绘制）
- 背景图 import：VRAM 压缩（CTex）+ mipmap + linear filter

### 主题（themes/main_theme.tres）

- 默认字体 Noto Sans SC，fallback 链保留 Godot 默认字体兜底生僻字符
- 配色（对齐背景图克苏鲁风）：
  - 底色 `#0B120D`（暗绿黑）
  - 边框 / 强调 `#B08D4A`（古铜金）
  - 正文 `#E8DCC0`（米金）
  - placeholder `#6B6455`（暗沙）
- 输入框 StyleBoxFlat：暗底 + 1px 金边 + 圆角 4；focus 时边框提亮一档
- 按钮：主/次两种 StyleBox，hover / pressed 有亮度变化
- 主题挂场景根节点，后续大厅 / 游戏 UI 复用

### 错误处理

纯布局无运行时错误路径。字体 fallback 链兜底缺字情况。

## 验收标准

- [ ] `godot --headless --import` 通过，无资源导入错误
- [ ] 实际运行截图检查三种窗口尺寸：1920×1080、1280×720、2560×1080（超宽）——UI 居中、不裁切、不错位
- [ ] 交互冒烟：输入框可聚焦可输入；密码框显示圆点；placeholder 中文正常渲染；两个按钮 hover 有视觉反馈

## 后续版本预留（不在本版范围）

- 接口层：HTTPRequest 封装、JWT 持久化（桌面 `user://`）
- 注册入口（后端 `POST /api/v1/auth/register` 已就绪）
- Web 导出（浏览器侧 CORS 需后端加中间件）
