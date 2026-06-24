# Buddy Bots for L4D2

[English README](README.md)

Buddy Bots for L4D2 是一个 Left 4 Dead 2 的 VScript 模组原型，目标是让生还者 bot 更像“会一起打的队友”，而不是只会贴着玩家走的护航单位。

内部脚本命名仍然保留 `gxLdBot`，对外项目名使用 Buddy Bots for L4D2。

## 当前状态

当前版本：`0.7.0-player`

这是实验性项目，优先面向单人 / 本地 bot 测试。它不会替换 Source 引擎底层的生还者 AI，而是在原版 bot 之上，通过 VScript、cvar、事件回调、`CommandABot` 和带保护的 NetProps 操作去做行为引导。

## 设计目标

目标不是“不惜一切代价让 bot 更强”，而是让 bot 更像另一个玩家：

- 安全时会自己往路线前方推进一点；
- 队伍卡住时会表现出一点不耐烦和主动性；
- 每个 bot 有角色、性格和卡牌差异；
- 一旦有人被控、倒地或队伍承压，立刻回到救援和防守优先级。

一句话原则：随机化时机和风格，不随机化基本生存责任。

## 功能概览

- 默认 `player` 行为模式，更像主动的开黑队友。
- `escort` 旧版护航模式，可切回 0.6.3 风格。
- `safe` 保守调试模式。
- bot 角色：point、flanker、follower、anchor。
- 每个 bot 有性格档案和 roguelike 风格卡牌。
- 可用地图 nav flow 时，bot 会基于流程距离主动推进。
- 单一动作仲裁器，统一处理移动、攻击、撤退、掩护、协助、推进、侦察、idle 和可选脚本救援。
- 人类玩家被控或倒地时，触发紧急防守。
- 特感控制、Tank/Witch、倒地、治疗意图等事件有语音 / 调试提示。
- 多人保护：检测到超过一名人类玩家时休眠并恢复 cvar。
- 聊天和控制台调试命令。

## 行为模式

`player` 是默认模式。它代表“主动玩家型队友”。

| 模式 | 用途 |
| --- | --- |
| `player` | 默认。更主动，更像开黑朋友或路人队友。 |
| `escort` | 旧 0.6.3 风格：更贴近人类玩家，推进更克制。 |
| `safe` | 保守调试模式：更短 lead、更安静、更少主动动作。 |

聊天切换：

```text
!hbot_mode player
!hbot_mode escort
!hbot_mode safe
```

开发者控制台切换：

```text
scripted_user_func hbot_mode_player
scripted_user_func hbot_mode_escort
scripted_user_func hbot_mode_safe
```

## 常用命令

本地 / 脚本游戏内聊天可用：

```text
!hbot_help
!hbot_status
!hbot_mode
!hbot_profile
!hbot_roles
!hbot_actions
!hbot_progress_status
!hbot_cards
!hbot_debug
!hbot_debugfile
!hbot_chat
!hbot_mpguard
!hbot_cvars
!hbot_scout
!hbot_progress
!hbot_actions_toggle
!hbot_rescue
!hbot_retreat
!hbot_cover
!hbot_shove
!hbot_assist
```

控制台请使用 `scripted_user_func`：

```text
scripted_user_func hbot_status
scripted_user_func hbot_mode_player
scripted_user_func hbot_mode_escort
scripted_user_func hbot_mode_safe
scripted_user_func hbot_actions
scripted_user_func hbot_progress_status
scripted_user_func hbot_cards
```

直接在 `]` 控制台输入 `!hbot_status` 报未知命令是正常的；那个位置只能运行 Source 控制台命令。

## 打包

覆盖已安装 VPK 前请先关闭 L4D2。游戏运行时会占用 addon VPK 文件。

只打包：

```powershell
.\build-vpk.ps1
```

打包并安装到默认 L4D2 路径：

```powershell
.\build-vpk.ps1 -Install
```

自定义路径：

```powershell
.\build-vpk.ps1 -VpkExe "F:\SteamLibrary\steamapps\common\Left 4 Dead 2\bin\vpk.exe"
.\build-vpk.ps1 -L4D2Path "F:\SteamLibrary\steamapps\common\Left 4 Dead 2" -Install
```

生成文件为 `gxldbot.vpk`。

## 手动安装

把 `gxldbot.vpk` 放到：

```text
Left 4 Dead 2/left4dead2/addons/gxldbot.vpk
```

然后重启游戏或重新加载地图。

## 快速测试

1. 关闭其他也包含 `director_base_addon.nut` 的脚本 addon。
2. 开一个本地地图，例如 `c1m1_hotel`。
3. 运行 `scripted_user_func hbot_status`。
4. 预期输出包含 `v0.7.0-player`、`mode=player`、`cards=true`、`progress=true`、`actions=true`、`rescue=false`。
5. 运行 `scripted_user_func hbot_mode_escort`，确认可以切回旧护航风格。

## 仓库结构

```text
gxLdBot/
  addoninfo.txt
  scripts/vscripts/director_base_addon.nut
  scripts/vscripts/gxldbot/*.nut
build-vpk.ps1
requirements.md
bot-ai-comparison.md
```

`gxLdBot/README.md` 是更长的开发记录。根目录 README 是公开仓库入口说明。

## 已知限制

- 瞄准和移动底层仍由游戏引擎控制。
- 基于 flow 的推进依赖地图 / nav flow 是否可用。
- 脚本救援已实现，但默认关闭；原版救援通常更稳。
- 物品拾取、投掷物经济、武器切换、完整战斗接管不是当前版本重点。
- 多人保护能降低风险，但加载屏阶段的 addon 冲突可能发生在 VScript 运行之前。

## 致谢与研究说明

项目设计参考了本地对现有 L4D2 bot addon 和 VScript 行为的研究。参考模组目录不包含在公开仓库中；本仓库只发布 Buddy Bots for L4D2 自身源码。

## 许可证

MIT。见 [LICENSE](LICENSE)。
