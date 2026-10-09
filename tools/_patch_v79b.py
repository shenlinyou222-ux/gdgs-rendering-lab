# -*- coding: utf-8 -*-
# v7.9b: 渐次出厂期间不得把空流过滤掉
import io

import os

# 仓库根目录（本脚本位于 tools/ 下，故取其上一级）
COMBAT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "solar_combat.gd")
NL = chr(10)

with io.open(COMBAT, "r", encoding="utf-8") as f:
    t = f.read()

OLD_F = chr(9) + "streams = streams.filter(func(x) -> bool: return is_instance_valid(x) and x.alive_count() > 0)"
NEW_F = chr(9) + "streams = streams.filter(func(x) -> bool: return is_instance_valid(x) and (x.alive_count() > 0 or _pending_members(x) > 0))   # v7.9b:出厂中的流不过滤"
assert t.count(OLD_F) == 1, "filter line mismatch"
t = t.replace(OLD_F, NEW_F)

HELPER = '''

func _pending_members(s) -> int:
	# v7.9b:该流还剩多少架未出厂(渐次创建期间 alive_count 可能为 0)
	for it in _spawn_q:
		if it["s"] == s:
			return s.members_n - int(it["i"])
	return 0
'''
t = t.rstrip(NL) + HELPER + NL
with io.open(COMBAT, "w", encoding="utf-8", newline="") as f:
    f.write(t)
print("OK v7.9b")
