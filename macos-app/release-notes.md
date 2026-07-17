## 主要改动

- **设置窗口支持为各来源自定义颜色**：在 Settings → Sources 中，每个来源右侧新增颜色块，点击后以弹出小窗的形式打开调色盘（色相/饱和度色轮 + 亮度滑块），选择的颜色会即时应用到 popover 中的来源标识。
- **修复首页数据卡片偶发消失问题**：优化了 Tokens 页面指标卡片的布局方式，避免在滚动时出现顶部卡片消失的显示异常。
- **修复设置窗口在多屏幕下的出现位置**：现在设置窗口会根据当前鼠标所在屏幕居中显示，避免在 A 屏幕打开后却在 B 屏幕显示的问题。
- **来源颜色持久化**：自定义颜色会保存到 `tokmon-ui-state.json`，并在 popover 的请求、会话、来源分布等位置使用。

## 校验值

`TokMon-0.2.17.dmg` SHA-256:
```
865c678368112f34a5f58161aa8d45b7e8ec85ebb872084aaf5bbb624ab6b8ef
```

Sparkle EdDSA 签名:
```
kVlL9pYVB327DYK1YT1URJ5iIGtJAAIR7WLplwLyky/yQqoeL0SYJJFCR1myOg4njp7Vjp9qp7M+mvstD/gXDA==
```
