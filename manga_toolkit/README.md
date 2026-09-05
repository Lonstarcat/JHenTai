# Manga Library Toolkit

Windows 11 漫画库维护工具。当前已完成基础框架、重复与 Unicode 分析、
画廊状态检查，以及名称整理、Metadata、目录检查、库对比、CBZ 和任务记录模块。

界面采用 Windows 11 风格的低饱和视觉系统，提供跟随系统、浅色、深色和黑白四种主题。黑白模式会同时移除按钮、选中状态、进度条和状态 Badge 的彩色语义。库扫描、画廊状态、重复检测和 Unicode 工具页面均使用统一标题区、筛选栏、状态 Badge、任务进度、空状态和详情侧栏。

## 项目结构

```text
manga_toolkit/
├── main.py
├── pyproject.toml
├── requirements.txt
├── requirements-dev.txt
├── app/
│   ├── core/       # 路径与日志基础设施
│   ├── models/     # 漫画目录、扫描、重复、Unicode 与画廊状态数据模型
│   ├── services/   # 扫描、分析、SQLite、状态检查、凭据、报表与工具检测
│   ├── workers/    # QThread 后台工作对象
│   ├── ui/
│   │   ├── components/ # 页面标题、侧栏、Badge、统计卡和详情面板
│   │   ├── pages/
│   │   ├── styles/     # light.qss / dark.qss
│   │   ├── widgets/
│   │   └── theme_manager.py
│   └── utils/
├── data/
├── logs/
├── reports/
└── tests/
```

## 安全边界

- 扫描器读取漫画库根目录下的一级漫画文件夹以及根目录中的 `.cbz` / `.CBZ` 文件。
- 每个漫画文件夹只统计其直接子文件，不递归读取图片或子目录。
- CBZ 扫描只读取 ZIP 中央目录及根层 metadata/ametadata，不解压图片；损坏 CBZ 仍会保留在扫描列表中供后续检查。
- 扫描不会移动、删除、重命名或修改任何漫画文件。
- 扫描被取消时，不用不完整结果覆盖 SQLite 缓存。
- 默认安全模式开启。
- 重复检测和 Unicode 分析只读取 SQLite 扫描缓存，不移动、改名或删除目录。
- 名称整理先生成 Short/Long 分类移动计划；目标冲突项不会执行，执行前必须确认。
- Metadata 修改只作用于用户选中的现有文件，写入前使用 `copy2` 备份到 `metadata_backup`。
- 目录检查和库对比均为只读操作。
- CBZ 打包不会删除源目录，已有目标默认跳过且不覆盖。
- 所有名称移动、Metadata 写入与 CBZ 打包结果都会进入 SQLite 操作日志。
- 画廊检查仅访问 EHentai/ExHentai，不会自动删除、移动、改名或替换本地目录。
- 登录 Cookie 只写入 Windows Credential Manager，不写入 `settings.json`、SQLite、日志或 Excel。

## Phase 2：重复与 Unicode 分析

“重复检测”按扫描阶段集中解析出的 ID 分组，支持分别启用：

- Normal ↔ Normal
- Archive ↔ Archive
- Normal ↔ Archive

结果按名称长度标记 `Short` / `Long`，用于后续安全生成整理计划；本阶段不会直接移动或重命名。页面支持搜索、按重复类型过滤、查看组详情并导出 Excel。

“Unicode 工具”统计 NFC、NFD 和 OTHER 状态，并通过 NFC 标准化后的名称识别 Unicode 编码重复。页面提供检测结果和重复组两个视图，可导出包含原名称、标准化名称与路径的 Excel。

Unicode 原地转换仍未开放；名称分类移动已通过独立计划、预览、确认和日志流程提供。

## 整理、Metadata 与目录检查

- “名称整理”以同类型同 ID 分组，生成 `Normal_ID/Archive_ID → Short/Long/Middle` 分类计划。默认输出到漫画库同级的 `处理中`，也可手动选择；分类完成后可再生成“Long 名称同步 Short”计划。执行后需重新扫描库。
- “Metadata”检查文件夹或 CBZ 根层的 `metadata` / `ametadata` 缺失、JSON 解析、标题、Unicode、空格、全角半角、标点和截断差异。CBZ 内 Metadata 只读；文件夹载体可对选中项修改 `groupName`。
- “目录检查”报告异常文件、子文件夹、无图片和读取失败；对 CBZ 额外检查损坏包、嵌套顶层和包内异常文件，不执行删除。
- 三个页面以及库对比、CBZ 检查均可导出 Excel。

## 库对比、CBZ 与任务记录

- “库对比”使用已扫描库作为 A，只读扫描用户指定的 B；默认按类型和 ID 比较，可选 Normal ↔ Archive。
- “CBZ 工具”调用用户在设置中配置的 `7z.exe`，压缩等级默认 Store (`-mx=0`)，并发默认 3（1～8 可选）。目标存在时断点跳过。
- 完整性检查验证 ZIP、空包、图片、Metadata、ComicInfo.xml、顶层结构和源/包文件数量。
- “任务记录”展示最近 5000 条写操作，可导出 Excel 或 UTF-8 CSV。

## 画廊状态检查

使用前先运行“库扫描”，程序会分别读取漫画一级目录中的 `metadata` 和 `ametadata`，从 JSON 内获取 `gid`、`token` 和 URL；不会根据文件夹名猜测 token。

1. 在“设置”中选择优先站点，默认 `exhentai.org`。
2. 如需检查 ExHentai，可输入 `ipb_member_id`、`ipb_pass_hash`、`igneous`，也可点击“网页登录 / Cloudflare 验证”。内嵌浏览器使用不落盘会话，只捕获这三个 Cookie，不读取或保存账号密码。
3. “测试登录状态”以受保护页面为主要证据：ExHentai 检查首页，E-Hentai 检查收藏页；同时识别异常重定向、Sad Panda、登录页和 Cloudflare 页面。论坛资料页只用于补充用户名，论坛被 Cloudflare 以 403 拦截时不再把有效站点会话误判为未登录。
4. 打开“画廊状态”，选择全部、仅失败项或选中项检查。
5. 可筛选最新版、有更新、不可用、访问受限、网络错误等结果，并导出 Excel。

从“库扫描”页面选择的新路径会在扫描成功后自动同步到设置和画廊状态页面；取消或失败的扫描不会替换当前漫画库路径。

检查器使用官方 `gdata` API，单批最多 25 项，并按设置中的请求间隔和批次暂停进行保守限流。仅当 API 结果可疑时才回退到画廊网页，以减少请求。默认缓存 24 小时；损坏或过期缓存会被忽略，不会中止其余任务。

Excel 只包含漫画路径、状态、画廊 URL、版本关系和错误摘要。画廊 URL 本身包含 gallery token，但不包含账户 Cookie；分享报表前仍应按私人库数据处理。

## 开发环境运行

```powershell
cd manga_toolkit
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python main.py
```

运行测试：

```powershell
python -m pytest
```

状态检查的网络测试使用 mock 响应，不会访问真实账号或站点。

使用 PyInstaller 构建 Windows 版本时，需要同时包含 QSS 主题资源：

```powershell
pyinstaller --noconfirm --clean --windowed `
  --name "Manga Library Toolkit" `
  --add-data "app/ui/styles;app/ui/styles" `
  main.py
```

## 应用数据

Windows 默认保存在：

```text
%LOCALAPPDATA%\MangaLibraryToolkit
├── app.db
├── settings.json
├── logs\
└── reports\
```

测试或便携运行时可设置 `MANGA_TOOLKIT_DATA_DIR` 覆盖数据目录。

## NAS / SMB

路径输入同时支持映射盘符（如 `Z:\JH`）和 UNC（如 `\\192.168.1.100\Manga`）。扫描并发为 1，不会对 NAS 发起并行目录遍历。Windows 端建议启用系统长路径支持。
