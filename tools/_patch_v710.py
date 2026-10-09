# -*- coding: utf-8 -*-
# v7.10: EVA 音量 / 核心暴露播报 / 查询类不应答 / 任务播报文案
import io

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
COMBAT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "solar_combat.gd")
NL = chr(10)
T = chr(9)

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

pairs = [
 ("_eva_voice.volume_db = 1.0",
  "_eva_voice.volume_db = 5.0   # v7.10:EVA 音量提升, 盖过加大的 BGM"),
 (T + "_eva_announce_key(" + chr(34) + "l1_clear" + chr(34) + ", true)",
  T + "get_tree().create_timer(1.5).timeout.connect(func(): _eva_announce_key(" + chr(34) + "l1_clear" + chr(34) + ", true))   # v7.10:核心暴露→爆炸余音后语音+字幕播报"),
 (T + "_eva_announce_key(" + chr(34) + "l2_clear" + chr(34) + ", true)",
  T + "get_tree().create_timer(1.5).timeout.connect(func(): _eva_announce_key(" + chr(34) + "l2_clear" + chr(34) + ", true))   # v7.10:同上"),
 (T + T + "_eva_ack()   # v7.7:EVA 指令应答",
  T + T + "if not ctype.begins_with(" + chr(34) + "eva_" + chr(34) + ") and ctype != " + chr(34) + "dbg_planet" + chr(34) + ":" + NL + T + T + T + "_eva_ack()   # v7.10:查询/播报类指令不应答(收到已完成)"),
 ("2: return " + chr(34) + "结算中: [1]火力 [2]装甲 [3]引擎" + chr(34),
  "2: return " + chr(34) + "结算中: [1-3]能力树 [4-6]改造, [Enter]跃迁下一关" + chr(34)),
 ("4: return " + chr(34) + "返航进入中转站核心即可跃迁" + chr(34),
  "4: return " + chr(34) + "返航!飞入虫洞(高斯球)内部完成跃迁" + chr(34)),
]

for old, new in pairs:
    n = t.count(old)
    if n != 1:
        print("FAIL count=%d: %r" % (n, old[:60]))
        raise SystemExit(1)
    t = t.replace(old, new)

with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
    f.write(t)
print("OK v7.10")
