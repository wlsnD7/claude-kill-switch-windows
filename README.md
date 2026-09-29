# Windows + Mihomo/Clash TUN：Claude 网络断线保护笔记

目标：代理不可用时，让 Claude Desktop 和 Claude Code 的请求失败，减少回落到直连出口的风险。

本文整理了按程序路径添加 Windows 防火墙规则、自动发现版本路径、隐藏启动监听器和登录计划任务的方法。**这是一套有条件的应用级 kill switch，不是经过证明的系统级 fail-closed 方案。** 新程序启动后才补规则，仍存在时间窗口；新增网卡、其他联网进程和代理内的 `DIRECT` 也可能绕过本文的保护范围。

适用环境：Windows、Windows PowerShell 5.1、具有管理员权限的目标用户、Mihomo 内核的 Clash 客户端。独立安装的 Claude Code 需要核对实际路径；WSL、容器和共享 `node.exe` 不自动包含在内。

本仓库不会在下载时安装任何东西。脚本需要读者配置、检查后手动运行。发布前进行了语法和模拟行为检查，未在本机部署防火墙或进行断网实测。

## 1. 原理与边界

正常情况下，希望流量沿下面的路径传输：

```text
Claude.exe → TUN → Mihomo → 已选代理节点 → 目标服务
```

TUN 消失时，Windows 可能重新选择其他出口。本文给已知 Claude 可执行文件添加出站阻止规则，使它们不能通过已列出的非 TUN 网卡直接联网。Mihomo 自己需要通过物理网卡连接代理，因此这些规则不针对 Mihomo。

这是设计意图。具体流量在 Windows 过滤层中如何匹配，还受 TUN 实现、接口、协议和本机策略影响，必须验证“代理正常可用”和“代理失效不能直连”两个方向，不能只看规则存在。

| 故障或变化 | 本文的处理 | 剩余限制 |
| --- | --- | --- |
| 代理节点故障，Mihomo 仍运行 | 专用策略组不包含直连出口 | 必须检查嵌套组、前置规则和实际连接记录 |
| Mihomo 退出或 TUN 消失 | 阻止已知程序通过已列出的其他网卡出站 | 未列出的网卡和未识别程序不受保护 |
| Claude 更新，完整路径改变 | 监听进程启动，补建新路径规则 | 新进程可能先发出请求，监听器无法消除这个窗口 |
| 监听器退出 | 旧规则保留，计划任务按设置重试 | 新版本路径不再自动获得保护；重试次数有限 |
| Mihomo 将请求按 `DIRECT` 转发 | 必须在 Mihomo 配置中避免 | Windows 针对 Claude 的规则不能阻止 Mihomo 自己直连 |

如果要求任意应用版本、任何启动时机都不能直连，需要另行设计系统级默认拒绝出口、隔离环境或网关策略，并处理代理自身、DNS、IPv6 和引导连接。本文不提供一条“封所有出站”命令冒充这种设计。

## 2. 先识别程序和网卡

在目标 Windows 用户的**管理员 Windows PowerShell**中查看：

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" |
    Select-Object ProcessId, Name, ExecutablePath

Get-Command claude -ErrorAction SilentlyContinue |
    Format-List Source, Path, CommandType

Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' } |
    Select-Object Name, Version, InstallLocation

Get-NetAdapter -IncludeHidden |
    Format-Table Name, InterfaceDescription, Status, ifIndex

Get-NetIPInterface |
    Format-Table InterfaceAlias, AddressFamily, InterfaceMetric, ConnectionState

Get-NetRoute -AddressFamily IPv4 |
    Format-Table DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
Get-NetRoute -AddressFamily IPv6 |
    Format-Table DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
```

不要只检查 `0.0.0.0/0` 和 `::/0`：拆分默认路由和更具体的路由也能成为出口。检查目前断开的网卡以及今后可能启用的以太网、无线、USB 网络共享和其他 VPN。

对话中观察到的路径类型如下，版本号和用户名必须以实际输出为准：

```text
Claude Desktop（某些打包安装）
C:\Program Files\WindowsApps\Claude_<版本>_<架构>__<包标识>\app\Claude.exe

由 Desktop 启动的 Claude Code（本例）
C:\Users\<用户>\AppData\Roaming\Claude\claude-code\<版本>\claude.exe
```

不能把第二种路径当成所有 Claude Code 安装的固定位置。独立 CLI 可能使用其他路径或启动器；若命令指向 `.cmd`、`.ps1`、符号链接或 `node.exe`，应继续确认实际联网进程。直接封锁共享 `node.exe` 会影响其他 Node 应用。

`Get-Command` 找不到命令不等于程序未安装。进程的 `ExecutablePath` 为空时，检查权限和进程是否已经退出。无法枚举某个目录也不能证明目录是临时的或已经被删除。

第一次准备保护规则时，应在隔离网络或已有可靠出口保护的条件下识别程序，避免为获取路径先让未保护程序联网。

## 3. Mihomo 配置

下面是合并到现有配置中的片段，**不是完整配置**。将 `PROXY_A`、`PROXY_B` 替换为已经存在、允许使用的实际代理节点名称。保留原来的 DNS 配置，避免重复 YAML 顶层键。

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
  # 接在后面的原有规则保持原顺序
```

将这些规则放在可能提前匹配的其他规则前面，并在客户端的合并结果中检查。订阅更新可能覆盖直接修改的配置，优先使用客户端支持的持久覆写方式。

专用组及其引用的嵌套组不得包含 `DIRECT` 或可能直连的兜底。`empty-fallback: REJECT` 处理的是组为空，不能解读成节点健康检查失败后自动切换到 `REJECT`。旧内核是否支持该字段需通过配置检查确认。[Mihomo 代理组文档](https://wiki.metacubex.one/config/proxy-groups/)

域名列表不保证穷尽登录、遥测、更新等请求；进程规则也依赖进程识别成功。检查连接面板中的进程、命中规则及完整代理链；其他进程代发请求时要另行分析。共享服务域名不宜不加区分地全部归入 Claude。

`strict-route` 在 Windows 下包含防止多宿主 DNS 泄漏的措施，但不能据此推导 Mihomo 崩溃后仍有系统级保护。官方也说明 Windows 的 DNS 劫持存在局域网 DNS 限制。[Mihomo TUN 文档](https://wiki.metacubex.one/config/inbound/tun/)

## 4. Windows 防火墙规则

本文选择**明确的网卡别名**，而不是直接假定 `Wireless` / `Wired` 等于所有物理网卡、并一定排除 TUN。`Radmin VPN` 只是可能存在的接口示例，不应照抄成每个人都必须有的网卡。

单条规则的含义可以用下面的命令理解。替换路径和接口后才运行；完整程序路径不能使用版本目录通配符。

```powershell
$programPath = 'C:\实际目录\claude.exe'
$egressAlias = '实际非TUN网卡名称'

New-NetFirewallRule -Name 'ClaudeKS-Manual-Example' `
    -DisplayName 'Claude KillSwitch manual example' `
    -Group 'Claude KillSwitch manual example' `
    -Direction Outbound -Action Block -Enabled True -Profile Any `
    -Program $programPath -InterfaceAlias $egressAlias -Protocol Any
```

为每个目标程序路径和每个可能直连的接口建立规则；不要把 TUN 本身放进阻止列表。规则不限定地址族和协议，意图覆盖该接口上的 IPv4、IPv6、TCP、UDP，而不是仅拦 443/TCP。[Microsoft：New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)

不要创建“阻止 Claude 所有接口”后，再用“允许 TUN”尝试抵消它：普通显式阻止规则优先于冲突的允许规则。[Microsoft：防火墙规则优先级](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules)

下面的自动脚本管理独立规则组 `Claude Auto KillSwitch v2`。手工示例、原有旧版规则不在其管理范围内。

## 5. 自动刷新脚本

仓库中的文件：

| 文件 | 用途 |
| --- | --- |
| [KillSwitch.config.psd1](scripts/KillSwitch.config.psd1) | 非 TUN 网卡别名与额外完整程序路径 |
| [Update-ClaudeKillSwitch.ps1](scripts/Update-ClaudeKillSwitch.ps1) | 查找路径并创建或更新规则 |
| [Watch-ClaudeKillSwitch.ps1](scripts/Watch-ClaudeKillSwitch.ps1) | 登录后刷新一次，再监听进程启动 |
| [Run-ClaudeKillSwitch-Hidden.vbs](scripts/Run-ClaudeKillSwitch-Hidden.vbs) | 隐藏启动并等待监听器退出 |

在管理员 PowerShell 中，将仓库中的四个文件复制到受保护目录。下面假设当前目录是仓库根目录：

```powershell
$installDir = Join-Path $env:ProgramFiles 'ClaudeKillSwitch'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$files = @(
    'KillSwitch.config.psd1',
    'Update-ClaudeKillSwitch.ps1',
    'Watch-ClaudeKillSwitch.ps1',
    'Run-ClaudeKillSwitch-Hidden.vbs'
)
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path '.\scripts' $file) -Destination $installDir
}
Get-Acl -LiteralPath $installDir | Format-List
notepad (Join-Path $installDir 'KillSwitch.config.psd1')
```

这是首次安装步骤。更新已有安装前先停止任务、确认监听器已退出，并备份本地配置；不要用仓库的占位配置覆盖已核对的网卡列表。目录和其中的脚本、配置均不能允许普通用户随意写入，因为任务将以提升权限运行。不要把提升权限的任务直接指向普通用户可写的下载目录或 Git 工作目录。

配置示例如下，必须替换成自己的环境。不存在 Radmin VPN 就不填；其他直连接口不能遗漏。

```powershell
@{
    BlockedInterfaceAliases = @('WLAN', 'Ethernet', 'Radmin VPN')
    ExtraProgramPaths = @(
        # 'C:\已确认的独立Claude安装目录\claude.exe'
    )
}
```

在管理员终端先运行一次，确认没有错误：

```powershell
& "$env:ProgramFiles\ClaudeKillSwitch\Update-ClaudeKillSwitch.ps1"
```

刷新逻辑：

1. 从运行中的 `claude.exe` 收集已知 Desktop / 当前用户 Desktop 内置 Code 路径，并对全部不同路径处理，不只取第一个进程。
2. 对名为 `Claude` 的当前用户 Appx 包尝试预先读取 `app\Claude.exe`；如果包名不同，需调整识别或明确填写额外路径。
3. 合并 `ExtraProgramPaths`，按“完整路径 + 接口别名”生成固定规则名，重复运行不会不断新增同一规则。
4. 为新路径添加规则，保留旧路径规则。找不到程序不会删除已有规则；执行错误会上报，不全局静默忽略。

已识别运行进程的路径不要求再次通过 `Test-Path`。人工填写的额外路径必须自行确认正确，它并不因为写进防火墙就证明是实际联网程序。

规则列表会随版本变化累积。这是保留旧进程保护的选择。清理旧规则前必须确认旧版本不会继续运行，也不会回滚使用。修改配置去掉某网卡不会自动删除已有规则；重命名或新增网卡后要重新核对并手动刷新。

## 6. 事件监听器与隐藏启动

监听器先订阅 `Win32_ProcessStartTrace`，再进行首次扫描，以减少注册事件期间漏掉启动的机会。之后 `Wait-Event` 等待 Claude 启动，触发一次刷新；没有每分钟启动新 PowerShell 的计划触发器。

监听器不使用原示例的 `$Pid` 变量。PowerShell 变量名不区分大小写，`$PID` 是当前 PowerShell 进程的自动变量，不能拿来保存目标进程 ID。本文直接重新扫描所有符合条件的进程。[Microsoft：自动变量](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables)

也不使用“5 秒内丢弃所有事件”的全局节流，避免 Desktop 启动后紧接着启动 Code 时遗漏后者。Electron 子进程多时会重复刷新，这是当前简化实现的成本。互斥锁防止同一会话内重复监听。

VBS 的核心是：

```vbscript
result = shell.Run(command, 0, True)
WScript.Quit result
```

窗口样式 `0` 用于隐藏启动，`True` 让 VBS 等待 PowerShell，随后把退出码交回计划任务。原来的 `False` 会让启动器立即退出，因此任务显示成功并不能说明监听器还活着。完整代码见 [VBS 文件](scripts/Run-ClaudeKillSwitch-Hidden.vbs)。

错误记录在安装目录的 `watcher.log`。刷新失败时监听器退出为非零状态，供计划任务重试；已经存在的规则仍保留。日志不是持续心跳，安静期间没有新记录不代表监听器死亡。

## 7. 登录计划任务

仍在目标用户的管理员 Windows PowerShell 中执行。目标用户需具备管理员权限；不要使用另一管理员账户代替目标用户，否则 Appx、AppData 和登录触发用户可能不一致。

先检查旧任务和旧监听器：

```powershell
$taskName = 'Refresh Claude Kill Switch'
Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Watch-ClaudeKillSwitch.ps1*' } |
    Select-Object ProcessId, ExecutablePath, CommandLine
```

如果原来已有同名任务，先停止它：

```powershell
Stop-ScheduledTask -TaskName 'Refresh Claude Kill Switch'
```

旧 VBS 使用异步启动时，停止任务可能留下子进程。根据上面的完整命令行确认属于这个监听器后，单独用 `Stop-Process -Id <已确认的进程号>` 停止它。不要按名称结束所有 PowerShell。

确认后，注册任务；`-Force` 会替换同名任务，包括旧的周期触发器：

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
    -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
```

`ExecutionTimeLimit` 设为零用于常驻监听；失败重试 3 次，间隔 1 分钟，这不是每分钟刷新规则。它不能保证任何故障都自动恢复，达到重试上限后需要处理日志中的错误并手动启动。[Microsoft：计划任务设置](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)

VBS/Windows Script Host 在某些 Windows 版本或组织策略中可能不可用。此时不要依赖隐藏启动，也不要为此绕过组织策略；可由管理员改为合适的非交互任务或服务方式，并重新验证身份、权限及退出码传播。[Microsoft：wscript](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wscript)

## 8. 验证命令与故障测试

### 8.1 检查有效策略，而不只检查本地保存的规则

```powershell
Get-Service MpsSvc, BFE | Format-Table Name, Status
Get-NetFirewallProfile -PolicyStore ActiveStore |
    Format-Table Name, Enabled, DefaultOutboundAction, AllowLocalFirewallRules

$rules = @(Get-NetFirewallRule -PolicyStore ActiveStore |
    Where-Object { $_.Group -eq 'Claude Auto KillSwitch v2' })
$rules | Format-Table Name, Enabled, Direction, Action, Profile
$rules | Get-NetFirewallApplicationFilter | Format-Table InstanceID, Program
$rules | Get-NetFirewallInterfaceFilter | Format-Table InstanceID, InterfaceAlias
$rules | Get-NetFirewallInterfaceTypeFilter | Format-Table InstanceID, InterfaceType
$rules | Get-NetFirewallAddressFilter | Format-Table LocalAddress, RemoteAddress
$rules | Get-NetFirewallPortFilter | Format-Table Protocol, LocalPort, RemotePort
```

核对每个实际程序路径和每个目标接口都有启用的出站阻止规则。受管设备的策略可能限制本地规则合并；规则写入成功不等于有效策略采用了它。

### 8.2 检查监听器

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

常驻任务预期处于 `Running`，`LastTaskResult` 可能是运行中状态码，而不是 `0`。单独的 `0` 不能证明监听器持续工作，更不能证明没有直连。

### 8.3 验证真实网络行为

初次故障测试应在隔离环境或有额外出口控制的环境中进行，避免测试本身造成未知出口访问。保存工作后逐项测试：

| 场景 | 应观察到的结果 |
| --- | --- |
| 代理和 TUN 正常 | 新建请求成功；Mihomo 连接记录显示专用代理链，没有 `DIRECT` |
| 所有选定代理节点不可达 | 新建请求失败；没有物理接口上的 Claude 直连 |
| 停止 Mihomo / 关闭 TUN | 新建请求失败；物理接口抓包和防火墙事件支持阻断结论 |
| 恢复代理 | 新建请求恢复，不需要临时关闭防火墙 |
| 重启、重新登录 | 任务启动、监听器存在、规则与程序路径对应 |
| 升级 Claude 或新增接口 | 重新核对新路径、新接口及 IPv4/IPv6；不能沿用旧结论 |

同时测试 TCP、UDP/QUIC（若应用使用）和 IPv6。检查已有长连接以及重新建立的连接。仅仅看到客户端转圈、缓存内容或连接错误，不足以证明零流量泄漏。

观察连接归属的辅助命令：

```powershell
$claudeProcessIds = @(Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" |
    Select-Object -ExpandProperty ProcessId)
Get-NetTCPConnection | Where-Object { $_.OwningProcess -in $claudeProcessIds } |
    Format-Table OwningProcess, LocalAddress, RemoteAddress, RemotePort, State
Get-NetUDPEndpoint | Where-Object { $_.OwningProcess -in $claudeProcessIds } |
    Format-Table OwningProcess, LocalAddress, LocalPort
```

这些瞬时列表会漏掉短连接，也不能直接证明物理出口。需要结合物理接口抓包、Windows 防火墙丢弃日志/过滤平台审计和 Mihomo 日志分析；抓包和日志可能包含敏感数据，不应直接公开上传。

## 9. 已知限制与安全注意事项

- 新路径出现到规则创建完成之间有竞态。事件监听和预扫描只能缩小部分窗口，无法使首次运行严格 fail-closed。短命进程可能在扫描前退出，无法补建规则。
- Windows 登录时程序可能比监听器更早启动；旧路径已存在的持久规则仍可起作用，新路径没有这种保证。
- 别名列表不是“除 TUN 外的所有网卡”。新增、重命名、USB 共享、其他 VPN 和路由变化都需要复核；仅发生网卡变化不会触发本监听器。
- 本例识别的路径是有范围的经验规则，不是身份验证或完整安装清单。新安装形式需要更新识别或明确填写完整路径。
- WSL、容器、浏览器登录、更新器、MCP 工具、子进程、共享 Node 运行时或本地代理代发请求均不能自动视为已保护。
- 程序规则不能保证由系统 DNS 服务或其他进程代发的 DNS 全部受控；DoH、局域网 DNS、IPv6 与 DNS 启动解析需独立验证。
- 本地代理即使只监听回环地址，也可能代表应用直连。应用侧规则不能代替对代理路由策略的检查。
- 监听器采用当前用户、当前会话的互斥锁；本文面向单用户会话。多用户、多会话、服务账户部署需要单独设计规则管理和锁范围。
- 防火墙关闭、组织策略覆盖、管理员修改规则或驱动行为变化均可能改变结果。日志可帮助发现故障，但不构成防篡改审计。
- `ExecutionPolicy Bypass` 只用于这次经过审阅的启动，不应被理解为安全校验。对脚本签名、组织执行策略有要求时应按环境调整。
- 持久规则和运行日志会保留本机路径，管理员应定期检查；日志没有自动轮转。分享时去除用户名、IP、代理订阅、令牌和命令行中的秘密。
- 网络断线保护不能保证账号不会被限制，也不改变服务的使用条件。公开技术笔记不能用来判断服务商的账号处置方式；本文不对国籍、所在地或封号概率作推断。

## 10. 停用与回滚

先停止任务，再检查监听器是否确实退出。停用监听器只停止未来刷新，旧防火墙规则仍保留。

```powershell
Disable-ScheduledTask -TaskName 'Refresh Claude Kill Switch'
Stop-ScheduledTask -TaskName 'Refresh Claude Kill Switch'
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Watch-ClaudeKillSwitch.ps1*' } |
    Select-Object ProcessId, CommandLine
```

如有残留，只结束已核实的监听器 PID。确认退出后，先预览本版本的规则：

```powershell
$ownedRules = @(Get-NetFirewallRule -PolicyStore PersistentStore |
    Where-Object { $_.Group -eq 'Claude Auto KillSwitch v2' })
$ownedRules | Format-Table Name, DisplayName
$ownedRules | Remove-NetFirewallRule -WhatIf
```

**下面的删除会撤销本文的应用出站保护。** 仅在已经准备好替代保护或确认需要卸载时执行：

```powershell
$ownedRules | Remove-NetFirewallRule
Unregister-ScheduledTask -TaskName 'Refresh Claude Kill Switch' -Confirm
```

原对话中的 `Claude Code Current`、旧 `Claude Auto KillSwitch` 规则和手工示例不会被这个规则组清理命令删除。请逐条检查，避免误删其他规则或因遗留规则误判新版配置。

## 11. 相比最初脚本的修正

- 不复用 `$PID`，不全局吞掉异常。
- 新旧路径各自保留规则，不以删除旧规则作为刷新前提。
- 处理所有匹配路径，避免只保护第一个进程版本。
- 明确配置网卡别名，不保证 `Wired` 一定排除虚拟接口。
- 订阅事件后再扫描，不用全局 5 秒丢事件节流。
- VBS 等待子进程并传播退出码，任务允许常驻并有限重试。
- 把脚本放在受保护目录，不把提高权限的常驻任务绑定到普通用户可写脚本。
- 将“规则存在”“有效策略采用”“故障时阻断”区分验证，不声称零窗口或绝对防泄漏。
