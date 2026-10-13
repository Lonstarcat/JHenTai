# Enhanced package identity migration

Install identity: `com.lonstarcat.jhentai`. The Dart package remains `jhentai`;
the server authentication `X-App-Id` remains `jhentai`. The displayed name and
original author attribution are unchanged. No database schema or manga metadata
format is changed. Old data is never automatically copied, moved or deleted.

## 安装与数据安全

- Android/iOS 是独立新应用，不是旧包的覆盖升级。先备份，保留旧应用，
  验证新应用的设置、漫画、下载任务正常后，再自行决定是否卸载旧应用。
- 权限、应用链接默认打开、通知设置需要对新应用重新授权。
- 不要让两个应用同时下载、整理或删除同一个漫画目录。
- 仅改 `.app` 的 Bundle ID 不会改变 `JHenTai.app` 的文件名；macOS 并存
  时将新旧应用放在不同目录，避免 Finder 覆盖旧应用。
- 7-Zip/ZIP 解压 Windows 版时也请选择新目录，勿覆盖旧程序目录。

## 各平台数据位置

| 平台 | 旧数据位置 | 新数据位置 |
|---|---|---|
| Android | `/storage/emulated/0/Android/data/top.jtmonster.jhentai/files/` | `/storage/emulated/0/Android/data/com.lonstarcat.jhentai/files/` |
| macOS（非沙箱版） | 用户 Documents 中的应用文件 | `~/Library/Application Support/com.lonstarcat.jhentai/` |
| Windows | `%APPDATA%\top.jtmonster\jhentai\` | `%APPDATA%\com.lonstarcat\jhentai\` |
| iOS | 旧应用的 Documents 容器 | 新应用的 Documents 容器 |

历史 macOS 沙箱版可能使用
`~/Library/Containers/top.jtmonster.jhentai/Data/Documents/`，请确认旧版实际
使用哪个数据库，不要把公共 Documents 目录内所有文件都复制过去。
下载路径仍可手动指定，漫画不会因包名修改自动移动或改名。

## 手动迁移（可选）

1. 停止旧版下载/收藏任务，退出新旧两个应用。备份旧数据目录及漫画。
2. 若只想恢复漫画：将漫画放在新应用可访问的目录，设置下载/额外扫描路径，
   使用现有“恢复下载任务”。此方式不迁移登录凭据和全部设置。
3. 若需要完整本地状态：在两应用均关闭时，将 `db.sqlite`、若存在的
   `db.sqlite-wal`/`db.sqlite-shm`、`jhentai.gs`、`jhentai.bak`、
   `jhentai.version` **复制**到新数据目录。先备份新目录中同名文件；
   不覆盖已有重要新数据。不要修改数据库内容、手工改 metadata 或删除源文件。
4. 数据包含旧的绝对下载路径。Android 旧包专属目录不能作为新包长期下载路径；
   需要复制漫画到新包可访问位置，再设置路径并恢复任务。iOS 也不能直接
   引用旧应用的私有容器路径。
5. 只启动新应用，确认登录/设置和漫画访问、分组、任务状态；异常时关闭新应用，
   恢复备份。不要用“恢复下载任务”代替完整配置/数据库备份。

Android 11+ 对其他应用的 `Android/data` 访问有限制。新应用不会绕过此限制；
应在旧应用仍安装时用具备权限的系统/设备工具备份，不能假设普通文件选择器
或新应用能直接读取旧目录。配置/数据库可能包含 Cookie，请勿上传到 GitHub。

## 发布与更新来源

- 更新检查、下载跳转、Obtainium 现在指向 `Lonstarcat/JHenTai`。
- 此次之前的增强版 Release 产物仍是旧包名；不自动替换、删除或上传 Release。
- AltSource 使用新 Bundle ID，但 `versions` 暂时为空，**不是可安装的正式源**。
  请先发布经验证 Bundle ID 为 `com.lonstarcat.jhentai` 的新 IPA，再填写实际
  `version`、`buildVersion`、发布日期、下载 URL、大小（字节）。不要引用旧 IPA，
  不要按 Release 标题猜测标签名，现有标签与文件版本可能不同。
- 新包仍由已有 Android Release 密钥签名。IPA 未签名，需自行签名；正式 Apple
  签名需要新 Bundle ID 对应的 App ID/描述文件，不使用上游 Team 作为自己的凭据。
- macOS 本地构建维持 12+、通用 Intel/Apple Silicon；本机 IPA 构建使用 iOS 15+。

## CI、Linux 与验证

仅推送 `feature/enhanced`，不推送标签。分支工作流仅有 Windows x64 Release，
Windows 产物为单层 ZIP。上游发布/Fastlane 工作流保持停用，不构建 Linux。
Linux GTK/AppImage/桌面标识已更新，但 DEB 包名/安装路径仍保留原设置；未来
若要与上游 Linux 包并存，应另行分离安装路径、DEB 包名和启动命令。

验证新 Android Manifest 包名/Provider、Kotlin 与 Dart 通道、macOS/iOS Bundle ID、
桌面数据目录隔离、有效 Obtainium JSON、Windows-only 工作流。单元测试不访问
真实漫画库，不进行真实文件迁移。安装后再手动测试权限、分享、音量翻页、
通知暂停/继续/点击定位、漫画路径和恢复任务。

## English summary

This is a separate install, not an in-place update. Back up old data before
uninstalling. Desktop storage is isolated; there is no automatic migration.
Keep both apps closed while copying databases/settings, preserve any SQLite
sidecars, and fix old absolute download paths before use. Do not run both apps
against the same writable library. New Android/iOS installs need fresh permissions.
Existing metadata and the upstream API protocol remain compatible.

Use release assets built after this migration. The AltStore/SideStore feed is
pending a published IPA with the matching bundle ID; it intentionally does not
advertise old signed identities as new ones. No release assets are automatically
uploaded or replaced. Windows alone builds in Actions; other requested packages
build locally. Linux builds and independent DEB installation remain out of scope.
