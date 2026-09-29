# Windows + Mihomo/Clash TUN：Claude 断线保护安装教程

按本教程依次完成：下载脚本 → 配置TUN → 确认网卡和程序 → 安装防火墙规则 → 设置隐藏监听及登录自启 → 验证。

目标是在代理失效时让Claude Desktop/Claude Code连接失败，减少回落到直连的风险。**这是有条件的应用级kill switch；新版本进程启动到规则补建之间仍有时间窗口，不能保证严格、零泄漏的系统级fail-closed。**

仓库不会在下载时自动安装。想自己安装，从[第 0 步](#step-0)开始按顺序操作；想让Agent安装，复制下面整段消息。

<a id="agent-install"></a>
## 通过Agent安装

将以下整段文字发给**能操作这台Windows电脑、有本地文件和终端权限的Agent**：

```text
请在我当前这台 Windows 电脑上实际安装并配置这个仓库的Claude断线保护，不要只给我教程：
https://github.com/wlsnD7/claude-kill-switch-windows
先读取当前 README 和全部 scripts 文件，核对行为，再按安装及验证步骤执行。目标是保护当前 Windows 用户使用的Claude Desktop/Claude Code。我授权你检查本机网络和程序、下载并审阅仓库、备份相关旧配置、在受管理员保护的目录安装脚本、配置本项目的 Windows 防火墙规则，以及创建或更新 Refresh Claude Kill Switch 登录计划任务。需要管理员权限或工具沙箱授权时，使用正常权限申请，不要绕过。请自行识别实际 TUN、其他可能直连的网卡以及 Claude 的完整联网程序路径。不要照抄 WLAN、Ethernet、Radmin VPN 或版本目录，不要把 TUN 加入阻止列表，不要封锁共享 node.exe。当前识别不覆盖的安装形式请明确处理；无法确定时只问我必要的问题。检查 Mihomo/Clash 的实际生效配置。备份后，为 Claude 配置不含 DIRECT 或直连兜底的专用代理策略和前置规则，确保订阅刷新后仍保留。沿用我已有且允许使用的代理节点，不能确定选哪个时再问我。不要公开订阅地址、节点凭据、令牌、日志或个人信息。若已有旧安装，先核对并备份配置、任务和相关规则，再停止已确认身份的旧监听器。不要覆盖未知任务、删除无关规则或结束全部 PowerShell。不要让提升权限的任务执行普通用户可写的脚本。刷新规则时保留旧路径保护。不要擅自关闭代理、断网、注销或重启，这些操作可能中断我或你的会话。首次识别程序若需要启动未受保护的程序，先说明隔离安排；需要上述中断操作时，告诉我具体动作和影响，等我同意。没有条件安全做断线测试时，完成静态检查并记为未实测，不能宣称绝对防泄漏。安装后检查 ActiveStore 中每个目标路径/接口的有效阻止规则、计划任务、唯一监听器和日志，并核对正常请求的 Mihomo 代理链。最后汇报安装目录、覆盖路径和接口、任务状态、已验证和未验证项目，以及停用/回滚命令。不要把规则存在或任务返回 0 当作零泄漏证明。
```

<a id="step-0"></a>
## 第 0 步：准备环境和管理员终端

开始前确认：

- 已安装Claude Desktop或Claude Code。本文从零安装的是断线保护，不负责安装Claude或提供代理节点。
- 已安装使用Mihomo内核的Clash客户端，且现有代理能够正常联网。
- 当前Windows用户有管理员权限。不要改用另一个管理员账户，否则用户路径与任务会对应到另一个人。
- 已保存工作，准备好在识别程序时暂时断开网络。

按Windows键，搜索**Windows PowerShell**，右键选择**以管理员身份运行**。使用 **64位Windows PowerShell 5.1**。后续代码块按顺序在这一个窗口执行，不要混用PowerShell 7或命令提示符。

```powershell
$ErrorActionPreference = 'Stop'
$PSVersionTable.PSVersion
[Environment]::Is64BitProcess
[Security.Principal.WindowsIdentity]::GetCurrent().Name
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) { throw '请重新以管理员身份打开 Windows PowerShell。' }
Get-Service MpsSvc, BFE | Format-Table Name, Status
Get-NetFirewallProfile -PolicyStore ActiveStore |
    Format-Table Name, Enabled, AllowLocalFirewallRules
```

**继续条件：**版本为 5.1、64 位结果为 `True`、账户正确，两项服务为 `Running`，相关防火墙配置文件已启用。受组织管理且禁止采用本地规则的设备，需要管理员处理策略。

## 第 1 步：下载仓库并进入正确目录

不需要 Git：

1. 打开[仓库首页](https://github.com/wlsnD7/claude-kill-switch-windows)，点击 **Code → Download ZIP**，或[直接下载 ZIP](https://github.com/wlsnD7/claude-kill-switch-windows/archive/refs/heads/main.zip)。
2. 在资源管理器中右键 ZIP，选择**全部解压缩**。
3. 打开解压后的内层文件夹，直到同时看到 `README.md` 和 `scripts`。
4. 点击资源管理器地址栏，复制该目录完整路径。
5. 在管理员 PowerShell 执行下面代码，按提示粘贴路径，不要带外层引号。

```powershell
$repoDir = Read-Host '粘贴同时包含 README.md 和 scripts 的目录路径'
Set-Location -LiteralPath $repoDir
$repoDir = (Get-Location).Path
if (-not (Test-Path -LiteralPath '.\scripts\Update-ClaudeKillSwitch.ps1')) {
    throw '目录不正确，请进入包含 scripts 的仓库根目录。'
}
Get-ChildItem -LiteralPath '.\scripts' | Select-Object Name
```

**预期结果：**看到以下四个文件。先打开阅读，确认内容和来源，再继续。

| 文件 | 用途 |
| --- | --- |
| [KillSwitch.config.psd1](scripts/KillSwitch.config.psd1) | 阻止的网卡别名和额外程序路径 |
| [Update-ClaudeKillSwitch.ps1](scripts/Update-ClaudeKillSwitch.ps1) | 发现路径并创建或更新规则 |
| [Watch-ClaudeKillSwitch.ps1](scripts/Watch-ClaudeKillSwitch.ps1) | 监听 Claude 启动并刷新规则 |
| [Run-ClaudeKillSwitch-Hidden.vbs](scripts/Run-ClaudeKillSwitch-Hidden.vbs) | 隐藏启动并传递退出码 |

确认后，只解除这四个文件的下载标记：

```powershell
$scriptFiles = @(
    'KillSwitch.config.psd1',
    'Update-ClaudeKillSwitch.ps1',
    'Watch-ClaudeKillSwitch.ps1',
    'Run-ClaudeKillSwitch-Hidden.vbs'
)
foreach ($file in $scriptFiles) {
    Unblock-File -LiteralPath (Join-Path "$repoDir\scripts" $file)
}
```

## 第 2 步：配置Mihomo/Clash

这一步在你的代理客户端中操作，菜单名称因客户端而异：

1. 备份当前配置，记下可用代理节点的准确名称。
2. 在TUN设置中启用 **TUN、Auto Route、Auto Detect Interface、Strict Route**。
3. 使用客户端支持的持久覆写/合并功能，合并下面的片段。将 `PROXY_A`、`PROXY_B` 换成已有节点名称；只有一个节点就删除 `PROXY_B` 那行。
4. 将五条新规则放在其他可能提前匹配的规则前面，保留原有后续规则和 DNS 配置。
5. 保存、检查配置、重新加载。打开最终生效配置，确认组、规则和 TUN 设置确实存在。

```yaml
find-process-mode: strict

tun:
  enable: true
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  dns-hijack:
    - any:53
    - tcp://any:53

proxy-groups:
  - name: Claude-KillSwitch
    type: fallback
    proxies:
      - PROXY_A
      - PROXY_B
    url: https://cp.cloudflare.com/generate_204
    interval: 30
    timeout: 3000
    empty-fallback: REJECT

rules:
  - PROCESS-NAME,claude.exe,Claude-KillSwitch
  - PROCESS-NAME,Claude.exe,Claude-KillSwitch
  - DOMAIN-SUFFIX,anthropic.com,Claude-KillSwitch
  - DOMAIN-SUFFIX,claude.ai,Claude-KillSwitch
  - DOMAIN-SUFFIX,claude.com,Claude-KillSwitch
  # 后面保留你的其他规则
```

这是片段，不是完整配置。已有 `tun`、`rules` 或 `proxy-groups` 时要合并，不要重复顶层键或覆盖整份订阅。不清楚持久覆写入口时，把客户端名称和版本告诉Agent，让它检查实际环境。

**继续条件：**加载成功，专用组及其引用链中没有 `DIRECT` 或直连兜底，订阅刷新也不会抹掉这些设置。`empty-fallback: REJECT` 处理组为空，不表示健康检查失败后动态切换为 `REJECT`；旧内核不支持时先解决兼容性。[Mihomo代理组文档](https://wiki.metacubex.one/config/proxy-groups/)

`strict-route` 在Windows下有阻止多宿主DNS泄漏的措施，但不代表Mihomo 退出后仍有系统级保护；Windows的DNS劫持也有局域网DNS限制。[Mihomo TUN文档](https://wiki.metacubex.one/config/inbound/tun/)

## 第 3 步：记录真实网卡名称

保持TUN开启，在管理员PowerShell执行：

```powershell
Get-NetAdapter -IncludeHidden |
    Format-Table Name, InterfaceDescription, Status, ifIndex
Get-NetIPInterface |
    Format-Table InterfaceAlias, AddressFamily, InterfaceMetric, ConnectionState
Get-NetRoute -AddressFamily IPv4 |
    Format-Table DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
Get-NetRoute -AddressFamily IPv6 |
    Format-Table DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
```

记录 `Name` / `InterfaceAlias`，不要填写网卡描述：

| 接口 | 是否加入后面的阻止列表 |
| --- | --- |
| 当前Mihomo使用的TUN | 不加入 |
| 其他可能直连的接口 | 加入，包括暂时断开的Wi-Fi、以太网，以及可能提供出口的USB共享和其他VPN |

`WLAN`、`Ethernet`、`Radmin VPN` 都只是示例，不要照抄。不能只看默认路由，拆分默认路由和更具体的路由也能成为出口；不能假设虚拟接口都安全或 `Wired` 一定排除TUN。

**继续条件：**你能确认TUN身份和所有要阻止的接口。不确定时，让Agent分析输出后再继续。

## 第 4 步：确认Claude的完整程序路径

保存并结束Claude工作。为避免未保护程序在识别时联网，**先暂时断开 Wi-Fi、拔掉网线并断开其他外网出口**，再启动要保护的Desktop/Code，保留安装终端。本地Agent也可能依赖网络，应事先与它约定这一步。

断网后运行：

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" |
    Select-Object ProcessId, Name, ExecutablePath
Get-Command claude -ErrorAction SilentlyContinue |
    Format-List Source, Path, CommandType
Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' } |
    Select-Object Name, Version, InstallLocation
```

当前脚本主要自动识别以下路径类型：

```text
Desktop：
C:\Program Files\WindowsApps\Claude_<版本>_<架构>__<包标识>\app\Claude.exe

当前用户由 Desktop 启动的 Code：
C:\Users\<用户>\AppData\Roaming\Claude\claude-code\<版本>\claude.exe
```

独立 CLI 或其他位置需要把**实际联网进程的完整 `.exe` 路径**记下来，下一步填入 `ExtraProgramPaths`。`.cmd`、`.ps1`、符号链接可能只是启动器；不要直接封锁共享 `node.exe`。

**继续条件：**每个要保护的组件都有已确认路径。找不到命令不代表没安装；路径为空时检查权限或进程是否已退出。若断网后无法启动Code、无法确认路径，先停在这里，不要为了找路径直接恢复未受保护的联网。

## 第 5 步：安装文件并填写配置

以下是**首次安装**流程，在同一个管理员窗口中执行：

```powershell
$installDir = Join-Path $env:ProgramFiles 'ClaudeKillSwitch'
if (Test-Path -LiteralPath $installDir) {
    throw '安装目录已存在，请先按 README 的已有安装更新流程处理。'
}
$oldTask = Get-ScheduledTask | Where-Object { $_.TaskName -eq 'Refresh Claude Kill Switch' }
if ($oldTask) { throw '已有同名任务，请检查旧安装，不能直接覆盖。' }
New-Item -ItemType Directory -Path $installDir | Out-Null
foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path "$repoDir\scripts" $file) -Destination $installDir
}
Get-Acl -LiteralPath $installDir | Format-List
```

目录通常为 `C:\Program Files\ClaudeKillSwitch`。确认目录和四个文件未授予普通用户写入或修改权限。不要让提升权限的任务直接执行下载目录、Git工作目录等普通用户可写位置的脚本。

**先编辑下面代码，再执行：**

- 将 `你的非TUN网卡名称` 换成第 3 步确认的名字。多个接口例如 `@('Wi-Fi', 'Ethernet')`，不包含TUN。
- 自动识别覆盖全部程序时保留 `ExtraProgramPaths = @()`；否则填入准确完整路径，例如 `@('C:\实际目录\claude.exe')`。
- 版本目录不能用 `*`；路径中的单引号需要写成两个单引号。

```powershell
$configText = @'
@{
    BlockedInterfaceAliases = @('你的非TUN网卡名称')
    ExtraProgramPaths = @()
}
'@
$configPath = Join-Path $installDir 'KillSwitch.config.psd1'
Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
Get-Content -LiteralPath $configPath
```

**继续条件：**输出没有占位文字，接口和路径与前两步一致。配置写在安装目录，而非只改了下载的样例。这里的Windows PowerShell 5.1 UTF-8写入会带BOM，以避免中文名称被错误解码。

## 第 6 步：第一次建立并核对规则

保持隔离状态和目标进程，执行一次刷新。执行策略只作用于这个PowerShell子进程，不修改整台电脑的策略：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -NoProfile -ExecutionPolicy Bypass `
    -File "$installDir\Update-ClaudeKillSwitch.ps1"
if ($LASTEXITCODE -ne 0) { throw '规则刷新失败，请处理错误后再继续。' }

$rules = @(Get-NetFirewallRule -PolicyStore ActiveStore |
    Where-Object { $_.Group -eq 'Claude Auto KillSwitch v2' })
if ($rules.Count -eq 0) { throw '有效策略中没有本项目规则，不能继续。' }
$rules | Format-Table Name, Enabled, Direction, Action, Profile
foreach ($rule in $rules) {
    [pscustomobject]@{
        Name = $rule.Name
        Program = ($rule | Get-NetFirewallApplicationFilter).Program
        Interfaces = (($rule | Get-NetFirewallInterfaceFilter).InterfaceAlias -join ', ')
    } | Format-List
}
```

**继续条件：**刷新无错误，每个目标路径与每个要阻止的接口都有对应规则，显示 `Enabled=True`、`Outbound`、`Block`、`Profile=Any`。TUN不应出现在阻止接口条件中。

例如首次安装有 2 个不同程序路径、3 个阻止接口，应有 6 条对应规则；后续旧版本规则会累积，不能只数条数。

看到 `No matching executable found` 或 `Refreshed 0 executable path(s)` 表示没有找到目标，不代表成功。核对当前账户、进程和额外路径。受管设备可能不采用本地规则，因此这里检查 `ActiveStore`。

## 第 7 步：设置隐藏监听和登录自启

确认第 6 步通过后，执行：

```powershell
$taskName = 'Refresh Claude Kill Switch'
$installDir = Join-Path $env:ProgramFiles 'ClaudeKillSwitch'
$vbsPath = Join-Path $installDir 'Run-ClaudeKillSwitch-Hidden.vbs'
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\wscript.exe" `
    -Argument ('//B //NoLogo "{0}"' -f $vbsPath) `
    -WorkingDirectory $installDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId `
    -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action `
    -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
```

首次安装故意不加 `-Force`，避免覆盖未知同名任务。任务在当前用户登录时启动，立即刷新一次，之后等待进程启动事件。没有每分钟刷新触发器；1分钟是失败重试间隔，最多3次。零运行时限允许常驻。[Microsoft：计划任务设置](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)

## 第 8 步：检查后台是否真的运行

等几秒后执行：

```powershell
Get-ScheduledTask -TaskName 'Refresh Claude Kill Switch' |
    Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName 'Refresh Claude Kill Switch' |
    Format-List LastRunTime, LastTaskResult
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Watch-ClaudeKillSwitch.ps1*' } |
    Select-Object ProcessId, ExecutablePath, CommandLine
Get-Content "$env:ProgramFiles\ClaudeKillSwitch\watcher.log" -Tail 30
```

**预期结果：**任务为 `Running`，当前会话只有一个属于本安装的监听器，命令行指向安装目录；日志含 `watcher started; initial refresh completed` 且没有后续 `ERROR`。

常驻任务的 `LastTaskResult` 可以是运行中状态码，不要求为 `0`。只有任务存在或返回 `0` 都不足以证明监听器正常。

若任务迅速结束、没有日志，检查动作路径和任务历史。某些Windows环境或组织策略不允许VBScript/Windows Script Host，不要绕过策略；需要管理员改用适当的非交互任务或服务方案，并重新验证账户、权限和退出码传播。[Microsoft：wscript](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wscript)

## 第 9 步：恢复网络并验证

### 先验证正常使用

1. 确认每个目标路径都已受到第 6 步的有效规则保护，监听器运行正常。
2. 关闭用于识别路径的Claude，恢复网络，先确认Mihomo的TUN和专用组正常。
3. 重新启动Claude，发起新请求。在Mihomo 连接面板核对实际进程、命中规则及完整代理链，不能出现 `DIRECT`。
4. 检查日志中的 `process event; refresh completed`，重新执行第 6 步的查询部分，确认当前程序路径仍被覆盖。

请求失败时检查是否误阻止TUN、路径是否错误、代理是否可用，以及旧的宽泛阻止规则。不要以关闭整个防火墙代替排错。

### 再验证断线行为

**只在隔离测试环境或已有额外出口控制时进行故障测试。** 保存工作，逐项测试，结束后恢复原配置。没有条件时记录为“安装及静态检查完成，断线行为未实测”，不要宣称零泄漏。

| 场景 | 应观察到的结果 |
| --- | --- |
| 所有选定节点不可达，Mihomo 仍运行 | 新请求失败，没有直连回退 |
| 关闭TUN或停止Mihomo | 新请求失败，物理接口抓包/防火墙事件支持阻断结论 |
| 恢复Mihomo和代理 | 新请求恢复，不需要关闭防火墙 |
| 保存工作后重新登录Windows | 任务和唯一监听器启动，规则匹配当前路径 |
| Claude升级或接口变化 | 重新核对路径、接口及IPv4/IPv6，不能沿用旧结论 |

需覆盖IPv4、IPv6、TCP、UDP/QUIC（若使用），并观察已有连接与新连接。客户端报错不等于零流量。结合物理接口抓包、防火墙丢弃日志/过滤平台审计及Mihomo日志分析，勿公开敏感原始日志。

## 日常维护与已有安装更新

新版本启动后，监听器尝试补建规则，保留旧路径保护。新增或重命名网卡后需要你修改配置并手动刷新，网卡变化本身不会触发监听器。

已有安装按以下顺序更新：

1. 在受保护的本地目录备份安装的四个文件、日志和任务定义；使用 `Export-ScheduledTask -TaskName 'Refresh Claude Kill Switch'` 导出任务XML，并记录本项目规则的应用和接口条件。备份可能含个人路径，不要上传。
2. 核对任务动作和监听器完整命令行，确认属于本项目，再停止任务。旧VBS异步启动可能留下子进程，只结束已经核实的监听器PID。
3. 替换受保护目录中的三个程序脚本，**保留并审阅原 `KillSwitch.config.psd1`**，不能用仓库的占位配置覆盖它。
4. 手动刷新并核对有效规则。若需要更新同名任务，完成备份和身份核对后，才在第7步的 `Register-ScheduledTask` 上加 `-Force`。
5. 重新执行第8～9步适用的检查。除非确认旧进程和回滚版本均不会使用，否则保留旧路径规则。

删除配置中的接口不会自动删除旧规则。原有 `Claude Code Current`、旧 `Claude Auto KillSwitch` 等规则也不由本版本自动清理，需单独核对。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 未配置网卡 | 修改安装目录中的配置，去掉占位符 |
| 禁止运行脚本 | 使用第6步的单进程执行策略；组织强制策略交由管理员处理 |
| 刷新0个程序 | 核对实际联网进程、账户和额外路径，不能直接继续 |
| 正常代理下Claude不通 | 检查是否误阻止TUN、代理链、路径和旧规则 |
| 任务结束且没有日志 | 检查wscript路径、脚本可用性和任务历史 |
| 日志出现ERROR | 处理具体错误后，再执行 `Start-ScheduledTask -TaskName 'Refresh Claude Kill Switch'` |
| 多个监听器 | 检查旧任务和完整命令行，仅停止已确认的重复实例 |
| 日志不增长 | 日志不是心跳，没有启动事件时不会新增记录 |
| 插入新网卡后保护不确定 | 更新接口列表，手动刷新并重新验证 |

## 原理与脚本行为

```text
正常：Claude.exe → TUN → Mihomo → 代理节点 → 目标服务
TUN 失效：已知 Claude.exe → 已列出的非 TUN 接口 → Windows 防火墙阻止
```

这是设计意图，实际是否按预期匹配取决于Windows过滤、TUN实现和本机策略，必须验证正常使用与故障两个方向。

规则按“完整程序路径 + 明确接口别名 + 出站 + 阻止”匹配，覆盖所有防火墙配置文件，未限定协议或地址族。`-Program` 不支持用版本通配符代替完整路径，所以脚本需要识别新路径。[Microsoft：New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)

脚本以路径和接口的哈希生成规则名，重复刷新不会持续增加相同规则；处理所有匹配版本，不先删旧规则。已运行进程提供的路径不要求再次通过文件存在检查；Appx预扫描仅针对当前用户名为 `Claude` 的包，其他安装需确认并补充路径。

监听器先订阅 `Win32_ProcessStartTrace` 再扫描，然后用 `Wait-Event` 等待启动。没有“5 秒内丢弃所有事件”的节流，避免遗漏紧接着启动的Code；代价是Electron子进程触发重复刷新。它不复用PowerShell自动变量 `$PID`。[Microsoft：自动变量](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables)

VBS用 `shell.Run(command, 0, True)` 隐藏启动、等待PowerShell，再传递退出码。若用不等待的 `False`，任务会提前结束。刷新失败会记日志、以非零状态退出，计划任务有限重试；旧规则保留。

不要创建“阻止所有接口”再试图用“允许TUN”抵消：普通显式阻止规则优先于冲突的允许规则。[Microsoft：规则优先级](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules)

## 已知限制与安全注意事项

- 首次运行、新版本和登录时的新路径可能先发请求再补规则。短命进程可能在扫描前退出，事件监听不能消除竞态。
- 未列出的出口不受保护，别名列表不自动追踪新增网卡或路由变化。
- Mihomo自己执行的 `DIRECT` 不会被针对Claude的规则阻止，因此代理配置是必要的一层。
- 浏览器登录、更新器、MCP工具、子进程、共享Node、WSL、容器和其他本地代理不自动受保护。
- 系统DNS服务代发请求、DoH、局域网DNS和IPv6需独立验证，程序规则不能证明全部受控。
- 当前设计面向单用户会话，互斥锁只覆盖当前会话；多用户、服务账户和多会话需另行设计。
- 防火墙关闭、组织策略覆盖、管理员修改规则或驱动变化均可能改变结果。
- `ExecutionPolicy Bypass` 不是安全校验；有签名或组织执行策略要求时按环境调整。
- 日志没有自动轮转；路径和日志可能包含个人信息。不要公开订阅、令牌、真实IP或未清理的诊断输出。
- 断线保护不能保证账号不会被限制，也不改变服务使用条件；本文不据此推断国籍、所在地或账号处置结果。

覆盖未知路径和所有启动时机，需要额外设计系统级默认拒绝出口、隔离环境或网关策略。本文没有部署这种系统级保护。

## 停用和卸载

先停止自动刷新，保留当前防火墙规则：

```powershell
Disable-ScheduledTask -TaskName 'Refresh Claude Kill Switch'
Stop-ScheduledTask -TaskName 'Refresh Claude Kill Switch'
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Watch-ClaudeKillSwitch.ps1*' } |
    Select-Object ProcessId, CommandLine
```

如有残留，用 `Stop-Process -Id` 加上已核实的监听器进程号结束它，不要停止所有PowerShell。确认退出后，预览仅属于本版本的规则：

```powershell
$ownedRules = @(Get-NetFirewallRule -PolicyStore PersistentStore |
    Where-Object { $_.Group -eq 'Claude Auto KillSwitch v2' })
$ownedRules | Format-Table Name, DisplayName
$ownedRules | Remove-NetFirewallRule -WhatIf
```

**以下操作将撤销这些程序的本项目出站保护。** 仅在已有替代保护或明确要卸载时执行：

```powershell
$ownedRules | Remove-NetFirewallRule
Unregister-ScheduledTask -TaskName 'Refresh Claude Kill Switch' -Confirm
```

确认任务和监听器不再存在后，可手动删除安装目录。其他旧版规则需逐条核对，不要重置整个防火墙。卸载不会还原第2步的Mihomo覆写，需要时用当时的配置备份恢复。

## 验证范围

仓库脚本经过PowerShell语法和模拟行为检查，覆盖重复刷新、多版本路径、空扫描保留规则和创建失败时报错。README的PowerShell代码块也经过语法检查。

这些检查不等于真实防火墙、VBScript、计划任务、Mihomo TUN和故障断网的端到端验证。请按本机环境完成第6～9步，并记录尚未验证的部分。
