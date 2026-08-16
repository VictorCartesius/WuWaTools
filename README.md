<a id="english"></a>

# wuwa_gachalink

[English](#english) | [简体中文](#chinese)

`wuwa_gachalink` extracts a Convene History URL from Wuthering Waves' `Client.log`.

The script automatically locates the newest game log, supports both plain-text logs and the game's current XOR-obfuscated logs, and copies the extracted URL to the clipboard by default.

## Requirements

- Windows
- Windows PowerShell 5.0 or later
- Wuthering Waves installed
- Open the in-game Convene History page at least once before running the script

## Usage

Open PowerShell in the directory containing the script, then run:

```powershell
.\wuwa_gachalink.ps1
```

If automatic detection does not find the log, provide its full path:

```powershell
.\wuwa_gachalink.ps1 -LogPath "C:\path\to\Client.log"
```

To prevent automatic clipboard copying, use `-NoCopy`:

```powershell
.\wuwa_gachalink.ps1 -NoCopy
```

The extracted URL is printed to the console. It is normally a time-limited signed URL; do not share it publicly.

## PowerShell Execution Policy

If PowerShell blocks local scripts, you can enable `RemoteSigned` for your current user only:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

This does not require administrator privileges. If a trusted script downloaded through a browser is still marked as coming from the Internet, remove that mark with:

```powershell
Unblock-File -Path .\wuwa_gachalink.ps1
```

Do not use a global `Bypass` policy or disable security protections merely to run an unknown script. Review the script and download it only from a trusted source.

## Game Data and Scope

This script is a read-only local log extractor:

- It reads local game logs, installation-related registry entries, Steam/Epic installation information, and common game directories.
- It decodes log data in memory only.
- It does not modify game files, game configuration, the registry, or file permissions.
- It does not inject into, hook, patch, launch, automate, or otherwise interact with the game process.
- It does not access the network or send the extracted URL anywhere.

By default, the extracted URL is written to the system clipboard; use `-NoCopy` to disable that behavior.

This is an independent community project, not an official Kuro Games tool, and it has not been endorsed by Kuro Games. It is intended for learning, research, and organizing the user's own locally stored log data. Users are responsible for complying with Kuro Games' applicable terms, rules, and platform policies.

## Troubleshooting

If no URL is found:

1. Launch the game and open the Convene History page once.
2. Run the script again.
3. If needed, use `-LogPath` to specify `Client.log` manually.

For execution-policy errors, see [PowerShell Execution Policy](#powershell-execution-policy).

## Decryption Attribution

According to available attribution information, the XOR obfuscation/decryption method for `Client.log` was originally discovered by **@kyuxu**. Decoder implementation details were provided by **@RabbyDevs**.

The extractor is implemented entirely in PowerShell and requires no external utilities, compiled helper binaries, or separate decoder.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).

---

<a id="chinese"></a>

# wuwa_gachalink（鸣潮抽卡日志链接提取）

[English](#english) | [简体中文](#chinese)

从《鸣潮》（Wuthering Waves）的 `Client.log` 中提取抽卡历史（Convene History）链接。

脚本会自动查找最新的游戏日志，支持明文日志和游戏当前使用的 XOR 混淆日志，并默认将提取到的链接复制到剪贴板。

## 运行要求

- Windows
- Windows PowerShell 5.0 或更高版本
- 已安装《鸣潮》
- 运行脚本前，至少在游戏内打开过一次抽卡历史页面

## 使用方式

在 PowerShell 中进入脚本所在目录，然后运行：

```powershell
.\wuwa_gachalink.ps1
```

如果自动查找失败，可以手动指定日志的完整路径：

```powershell
.\wuwa_gachalink.ps1 -LogPath "C:\path\to\Client.log"
```

若不希望自动复制到剪贴板，使用 `-NoCopy`：

```powershell
.\wuwa_gachalink.ps1 -NoCopy
```

脚本会在控制台输出提取到的链接。该链接通常是有时效的签名链接，请勿公开分享。

## PowerShell 执行策略

如果 PowerShell 阻止运行本地脚本，可以仅为当前用户启用 `RemoteSigned`：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

这不需要管理员权限。若从浏览器下载的可信脚本仍被标记为来自互联网，可解除该标记：

```powershell
Unblock-File -Path .\wuwa_gachalink.ps1
```

不要为了运行未知来源的脚本使用全局 `Bypass`，也不要关闭系统安全机制。运行前请检查脚本内容，并仅从可信来源下载。

## 游戏数据与行为范围

本脚本是只读的本地日志提取工具：

- 只读取本地游戏日志、与安装位置有关的注册表项、Steam/Epic 安装信息和常见游戏目录；
- 仅在内存中解码日志数据；
- 不修改游戏文件、游戏配置、注册表或文件权限；
- 不注入、Hook、修补、启动、自动化或以其他方式与游戏进程交互；
- 不访问网络，也不会向任何地方发送提取到的链接。

默认会将提取到的链接写入系统剪贴板；使用 `-NoCopy` 可禁用此行为。

本项目是社区独立工具，不是库洛游戏官方工具，也未获得官方认可。项目用途定位为学习、研究以及整理使用者本人本地保存的日志数据。使用者应自行遵守库洛游戏的适用条款、规则和平台政策。

## 故障排除

如果找不到链接：

1. 启动游戏并打开一次抽卡历史页面。
2. 重新运行脚本。
3. 必要时使用 `-LogPath` 手动指定 `Client.log`。

如果出现执行策略错误，请参阅上面的“PowerShell 执行策略”说明。

## 解密方法致谢

根据现有致谢资料，`Client.log` 的 XOR 混淆/解密方法最初由 **@kyuxu** 发现，解码器实现细节由 **@RabbyDevs** 提供。

提取器完全使用 PowerShell 实现；除 Windows/PowerShell 自带功能外，不依赖外部工具、编译的辅助二进制文件或单独的解码器。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)（GPLv3）许可证。
