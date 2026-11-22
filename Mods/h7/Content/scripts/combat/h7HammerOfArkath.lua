local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Hammer of Arkath (Fire Giant)
---
--- After its own melee attack (counterattacks do not count; second strikes do) hits the target, all stacks and war machines adjacent to the target (friend or foe, the Fire Giant excepted,
--- arrow towers and invincible stacks excluded) take val% of this hit's actual damage as Fire damage (scaled by Fire reduction; Fire-immune stacks take none).
---
--- Parameter: val (percentage, default 50)

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter then return end
	local main = payload.targets and payload.targets[1]
	if main == nil or main.unit == nil or (main.damage or 0) <= 0 then return end
	local target = main.unit
	local base = math.floor(main.damage * (self.val or 50) / 100)
	if base <= 0 then return end

	local around = L.adjacentUnits(battle, target, function(o)
		return o:unitID() ~= unit:unitID() and L.damageable(o)
	end)
	for _, u in ipairs(around) do
		if u:isAlive() then
			local dmg = L.schoolDamage(u, base, "fire")
			if dmg > 0 then
				local dealt, killed = L.hit(server, battle, u, dmg, "h7/fx/h7HammerOfArkath", "")
				L.log(server, battle, 4, { L.name(unit), L.name(u) }, { dealt })
				L.perish(server, battle, u, killed)
			end
		end
	end
end

return Script
