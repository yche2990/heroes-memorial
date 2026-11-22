local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Withering Venom (Death Weaver); the same script is also registered as Poisoned Blades h7PoisonedBlades (Shadow).
---
--- Enemies hit by its attacks (counterattacks included): for the next turns rounds (default 3) they take Dark damage at the start of each round,
--- first perCreature x the attacker's count at the time, then the same amount more each round (4n, 8n, 12n), regardless of Attack and Defense.
--- Stacks immune to Dark (or to negative Dark spells) are not affected. Being poisoned again keeps the larger damage and increment, and the rounds restart.
--- Settled in combat/h7StatusTick (one copy battle-wide).
---
--- Parameters: kind (venom / blades, decides the display), perCreature, turns

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local kind = self.kind or "venom"
	local amount = (self.perCreature or 1) * unit:getCount()
	if amount <= 0 then return end
	local hit = false
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		if (entry.damage or 0) > 0 and L.canHit(battle, unit, t) and not L.schoolImmune(t, "dark") then
			L.applyDot(server, battle, unit, t, kind, amount, amount, self.turns or 3)
			server:showBattleAnimation(battle, { { unit = t } }, L.DOT[kind].anim, "", 1.0, true)
			hit = true
		end
	end
	if hit then server:refreshBattleUnits(battle) end
end

return Script
