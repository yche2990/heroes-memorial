local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Acid Breath, Withering Breath (Black Dragon, Shadow Dragon, Emerald Dragon); the same script is also registered as Acid Spit h7AcidSpit (Venom Wyvern).
---
--- Each enemy hit by its own attack (counterattacks excluded): at the start of the next round it takes pct% of this damage (default 50%),
--- and half of that (25%) at the start of the round after, regardless of Attack and Defense. Stacks immune to that school (or its negative spells) are not affected.
--- Being hit again keeps the larger damage and restarts the rounds. Settled in combat/h7StatusTick (one copy battle-wide).
--- h47Acid of the pack deals the same damage every round, unlike H7's "50%, 25%", so this is written separately.
---
--- Parameters:
---   kind    acid (Earth, shown as "Acid") / wither (Dark, shown as "Wither")
---   school  earth / dark
---   pct     percentage in the first round, default 50
---   turns   number of ticks, default 2

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() then return end
	local kind = self.kind or "acid"
	local pct = self.pct or 50
	local hit = false
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		local damage = entry.damage or 0
		if damage > 0 and L.canHit(battle, unit, t) and not L.schoolImmune(t, self.school or "earth") then
			local first = math.max(1, math.floor(damage * pct / 100))
			L.applyDot(server, battle, unit, t, kind, first, 0, self.turns or 2)
			server:showBattleAnimation(battle, { { unit = t } }, L.DOT[kind].anim, "", 1.0, true)
			hit = true
		end
	end
	if hit then server:refreshBattleUnits(battle) end
end

return Script
