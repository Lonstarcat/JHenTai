# Emangato

Windows 11 漫画库维护工具。当前已完成基础框架、重复与 Unicode 分析、
画廊状态检查，以及名称整理、Metadata、目录检查、库对比、CBZ 和任务状态模块。

界面采用 Windows 11 风格的低饱和视觉系统，提供跟随系统、浅色、深色和黑白四种主题。黑白模式会同时移除按钮、选中状态、进度条和状态 Badge 的彩色语义。库扫描、画廊状态、重复检测和 Unicode 工具页面均使用统一标题区、筛选栏、状态 Badge、任务进度、空状态和详情侧栏。

仪表盘汇总漫画总数、Normal、Archive、NFC、NFD、重复 ID、Metadata/ComicInfo 缺失、CBZ 数量、异常 CBZ、扫描异常和画廊更新。通用功能页的表格报告可导出为 Excel、UTF-8 CSV 或 JSON。

## 项目结构

```text
Emangato/
├── Emangato.png
├── Emangato.ico
├── Emangato.spec
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

“转换与合并”页现已提供四种经过预览和确认的操作：

- 输出 NFC 副本（默认）：复制整个漫画目录到新位置，再仅对目录名、`metadata`、`ametadata`、`ComicInfo.xml` 做 NFC 标准化；源数据不变。
- 原地转换 NFC：仅在高级模式开放，修改文本前自动备份，目标名称冲突时拒绝执行。
- NFC/NFD 分类移动：将规范化后同名的项目移动到 `Unicode匹配/NFC` 与 `Unicode匹配/NFD`。
- NFC/NFD 内容合并：输出到 `合并完成`，不删除两侧源目录；Metadata/ComicInfo 取修改时间较新者，图片取修改时间较旧者。同一 ID 组内多出的未配对项会原样复制到 `未合并/NFC` 或 `未合并/NFD`。

名称和 Unicode 移动会写入任务状态，可在“任务状态”选择成功记录反向恢复；恢复时绝不覆盖已存在的原路径。

## 整理、Metadata 与目录检查

- “名称整理”以同类型同 ID 分组，生成 `Normal_ID/Archive_ID → Short/Long/Middle` 分类计划。默认输出到漫画库同级的 `处理中`，也可手动选择；分类完成后可再生成“Long 名称同步 Short”计划。执行后需重新扫描库。
- “Metadata”按 JHenTai 类型规则检查：Normal 只检查 `metadata`，Archive 只检查 `ametadata`，未知类型才同时检查两者。它会报告缺失、JSON 解析、标题、Unicode、空格、全角半角、标点、截断和首个差异位置。CBZ 内 Metadata 只读；文件夹载体通过独立按钮执行 `metadata → 下载` 或 `ametadata → 归档`。
- Metadata 页面可独立备份选中目录，并可选择同时备份 `ComicInfo.xml`；备份使用 `copy2` 保留原修改时间。所有 JSON 修改均先备份再原子替换。
- “目录检查”报告异常文件、子文件夹、无图片和读取失败；对 CBZ 额外检查损坏包、嵌套顶层和包内异常文件，不执行删除。
- 三个页面以及库对比、CBZ 检查均可导出 Excel。

## 库对比、CBZ 与任务状态

- “库对比”使用已扫描库作为 A，只读扫描用户指定的 B；默认按类型和 ID 比较，可选 Normal ↔ Archive。库 B 在当前会话缓存，可手动刷新，避免在 NAS 上为对比和计划重复扫描。
- 跨类型匹配会同时显示 A/B 大小，并按可调整阈值给出保留建议：Archive 大于默认 50MB 时建议保留 Archive，否则建议保留 Normal；该规则不会用于同类型比较，也不会自动删除任何一方。
- “A ID → B 操作计划”会列出 B 中与 A 的数字 ID 匹配的一级项目。计划导出为 `匹配结果` Excel，`执行` 列默认全部为“否”；用户核对并改为“是”后必须重新导入。
- Excel 导入会校验列结构、重复源/目标、源路径必须位于当前库 B 一级、目标路径必须位于所选目标目录一级、源存在且目标不存在。执行阶段严格使用 Excel 固定路径，不重新匹配、不覆盖，并写入可恢复的操作日志。
- “CBZ 工具”调用用户在设置中配置的 `7z.exe`，压缩等级默认 Store（`-mx=0`），并发默认 3（1～8 可选），支持测试前 10/50/100 个或处理全部。
- 已有 CBZ 支持“跳过 / 重新生成 / 验证后决定”。重新生成始终先写入唯一临时文件；7-Zip 成功后才把旧包备份到 `cbz_backup` 并原子替换。任务中断后重新运行可通过“跳过”或“验证后决定”继续未完成项目。
- CBZ 调度支持暂停、继续和取消。暂停会停止投放新任务；已经启动的 7-Zip 进程会安全完成，避免强杀进程留下损坏包。取消同样等待当前有限数量的在途任务结束后停止。
- 完整性检查验证 ZIP、空包、图片、Metadata、ComicInfo.xml、顶层结构和源/包文件数量，同时列出缺少 CBZ 与没有对应原目录的多余 CBZ。
- 完整性结果支持“所有异常”及按异常类型筛选。缺少 ComicInfo 的原漫画目录和对应 CBZ 可分别选择复制或移动到隔离目录；执行前显示完整数量、冲突数量和源/目标预览，目标存在时拒绝覆盖。
- CBZ 同名目录整理支持复制或移动，例如 `A.cbz → A/A.cbz`；操作前显示计划和冲突，目标存在时拒绝覆盖。
- “任务状态”展示最近 5000 条写操作，可导出 Excel 或 UTF-8 CSV。

## 画廊状态检查

使用前先运行“库扫描”，程序会分别读取漫画一级目录中的 `metadata` 和 `ametadata`，从 JSON 内获取 `gid`、`token` 和 URL；不会根据文件夹名猜测 token。

1. 在“设置”中选择优先站点，默认 `exhentai.org`。
2. 如需检查 ExHentai，可输入 `ipb_member_id`、`ipb_pass_hash`、`igneous`，也可点击“网页登录 / Cloudflare 验证”。内嵌浏览器使用不落盘会话，只保存这三个 EH Cookie，不读取或保存账号密码；已有 Cookie 会先注入 WebView。
3. WebView 参考 JHenTai 的验证方式，直接读取页面中的游客标记和用户名，并在 ExHentai 页面排除 Cloudflare 挑战与 Sad Panda。浏览器内已经取得明确证据时不再重复用普通 HTTP 请求验证。普通“测试登录状态”仍以受保护页面为主要证据；论坛被 Cloudflare 以 403 拦截时不会把有效站点会话误判为未登录。
4. 打开“画廊状态”，选择全部、仅失败项或选中项检查。
5. 可筛选最新版、有更新、不可用、访问受限、网络错误等结果，并导出 Excel。

从“库扫描”页面选择的新路径会在扫描成功后自动同步到设置和画廊状态页面；取消或失败的扫描不会替换当前漫画库路径。

检查器使用官方 `gdata` API，单批最多 25 项，并按设置中的请求间隔和批次暂停进行保守限流。仅当 API 结果可疑时才回退到画廊网页，以减少请求。默认缓存 24 小时；损坏或过期缓存会被忽略，不会中止其余任务。

Excel 只包含漫画路径、状态、画廊 URL、版本关系和错误摘要。画廊 URL 本身包含 gallery token，但不包含账户 Cookie；分享报表前仍应按私人库数据处理。

## 开发环境运行

```powershell
cd Emangato
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

Windows 11 上可运行项目自带构建脚本。脚本会创建独立构建环境、运行测试、打包 PySide6/主题/凭据后端，并生成单层 ZIP：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build_windows.ps1
```

输出为 `dist\Emangato_Windows.zip`。构建必须在 Windows 11 执行；macOS 不能生成可直接运行的 Windows PyInstaller 程序。

提交到仓库的 `main` 分支后，GitHub Actions 的 **Build Emangato Windows** 工作流会自动运行；也可在 Actions 页面手动执行。产物名为 `Emangato_Windows`。

所有结果表格都支持右键打开“显示 / 隐藏列”和“排序项目”菜单；右键具体漫画行时，还可打开漫画文件夹或定位对应 CBZ。顶部右侧统一提供主题切换和安全/高级模式开关，安全模式默认开启。设置页只有在内容发生变化后才显示固定在顶部的“保存设置”按钮。

设置页可自动检测或手动指定 7-Zip、FFmpeg、FFprobe 和 Czkawka。Czkawka 仅作为外部重复文件/视频检测工具入口，本程序不会代替其相似视频算法。

## 应用数据

Windows 默认保存在：

```text
%LOCALAPPDATA%\Emangato
├── app.db
├── settings.json
├── logs\
└── reports\
```

测试或便携运行时可设置 `EMANGATO_DATA_DIR` 覆盖数据目录。

## NAS / SMB

路径输入同时支持映射盘符（如 `Z:\JH`）和 UNC（如 `\\192.168.1.100\Manga`）。扫描并发为 1，不会对 NAS 发起并行目录遍历。Windows 端建议启用系统长路径支持。
