# 🛠 System Repair — 跨平台系统修复脚本

一套跨平台系统诊断与修复工具，针对常见问题提供自动修复。按平台分为三个脚本，均带彩色日志输出和交互确认/菜单。

## 目录

| 脚本 | 目标平台 | 定位 |
| --- | --- | --- |
| `LinuxRepair.sh` | Termux / Linux | 系统自动修复（坏到底“worst case”版） |
| `WindowsRepair.sh` | Windows（Git Bash / WSL / MSYS2 / Cygwin） | 交互式修复菜单 |
| `MacRepair.sh` | macOS | 交互式修复菜单 |

---

## LinuxRepair.sh

覆盖 Termux 与常见 Linux 发行版（Debian/apt/dpkg 及其他包管理器）。

**诊断阶段**
- 系统类型识别（Termux / Linux）
- 基础工具检查（dpkg、apt、pkg、curl、wget）
- 动态链接器与 libc 检查
- dpkg 数据库完整性检查
- 网络连通性检查

**修复阶段**
- Termux：常规修复 / 深度修复 / 重建 dpkg 数据库
- Debian 系（apt/dpkg）：修复 apt、重建 dpkg 数据库、重装 apt、修复 libc
- 其他发行版：自动改用对应包管理器

**运行**

```
bash LinuxRepair.sh
```

脚本会先输出诊断报告，询问 `Start automatic repair? (y/N)`，输入 `y` 后按系统类型自动执行修复。

---

## WindowsRepair.sh

在 Windows 下通过 Git Bash / MSYS2 / Cygwin / WSL 运行，需管理员权限。

**功能菜单（选择式）**
1. 一键全量修复（推荐，约 30–90 分钟）
2. 系统文件检查器（SFC）
3. DISM 映像修复
4. 注册表备份与修复
5. 网络协议栈重置
6. WMI 仓库修复
7. 启动配置修复
8. 计划磁盘检查（chkdsk，需重启）
9. 重置 Microsoft Store 与应用缓存
10. 还原默认服务

**运行**

```
bash WindowsRepair.sh
```

按提示选择序号执行；一键修复会依次执行 SFC、DISM、注册表、网络、WMI、服务、Store、启动配置，并询问是否预约 chkdsk。

---

## MacRepair.sh

仅在 macOS（Darwin）下运行，需要 `sudo` 权限。

**功能菜单（选择式）**
1. 一键全量修复（推荐）
2. 修复磁盘权限
3. 重建 Launch Services 数据库
4. 重建 dyld 共享缓存
5. 刷新 DNS 并重置网络
6. 校验钥匙串（Keychain）
7. 修复 Homebrew（如已安装）
8. 重置 App Store 缓存
9. 清理用户缓存

**额外提示**：脚本会检查 SIP 状态；`fsck` / NVRAM / 磁盘急救等操作需在恢复模式下手动执行，脚本会给出对应指引（Intel 与 Apple Silicon 的进入方式不同）。

**运行**

```
bash MacRepair.sh
```

---

## 通用说明

- 三个脚本均使用彩色日志（INFO / OK / WARN / FAIL），并在执行关键操作前二次确认
- 修复可能耗时较长（尤其 Windows 一键全量），请保持设备通电并避免中断
- 涉及权限的操作会提示需要管理员 / root / sudo
