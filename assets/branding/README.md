# 品牌资源

品牌名 **番茄端碗 / FanqieDuanwan**，视觉语言为「暖色玻璃（tomato glass）」：
番茄红 `#E8342A` → 琥珀橙 `#FF9F1C` 的渐变作底，中间一只白碗盛着一颗番茄，
直接对应「番茄的剧，端在碗里」。

`app_icon_source.png`（2048×2048）是设计原图。它不在 Flutter 的 assets
清单里，不会被打进安装包。

## 重新生成

```sh
python -m pip install Pillow
python scripts/generate_brand_assets.py
```

脚本一次生成以下资源（结果随源码提交，正常构建不需要 Python）：

| 产物 | 用途 |
|---|---|
| `assets/branding/app_icon_source.png` | 2048² 设计原图（不打包） |
| `windows/runner/resources/app_icon.ico` | Windows 可执行文件图标，含 16/24/32/48/64/128/256 七档 |
| `assets/images/app_logo.webp` | 应用内「关于」页与侧栏标识，384² |
| `assets/web/favicon.png` | 内置网页 favicon，64² |
| `windows/installer/wizard-large.bmp` | 安装向导左侧品牌图 164×314（24 位 BMP） |
| `windows/installer/wizard-small.bmp` | 安装向导右上角小图 55×55（24 位 BMP） |

## 设计约束

- **16/24/32 像素用简化版**：去掉番茄的叶片、梗与高光，只留下碗 + 圆形番茄
  并加粗描边，否则细节在小图标上会糊成一团。
- **BMP 必须是 24 位**：Inno Setup 不接受带 alpha 的向导图；脚本用 RGB
  保存，不要手工替换成 PNG 或 32 位 BMP。
- **窗口标题**在 `windows/runner/main.cpp` 里用通用字符名
  （`L"\u756A\u8304\u7AEF\u7897"` = 番茄端碗）书写，避免源码编码影响
  MSVC 解析；想改标题请沿用这个写法。
- **资源版本信息**（`windows/runner/Runner.rc`）用 ASCII 的 `FanqieDuanwan`：
  它决定 `%APPDATA%\<CompanyName>\<ProductName>` 数据目录，改成中文会让
  路径随系统区域变化。
