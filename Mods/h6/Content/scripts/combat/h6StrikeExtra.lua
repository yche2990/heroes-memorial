local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Attacks with extra effects (H6 Shadow "Poisoned Blade", Shadow Lurker/Watcher "Tormenting Gaze")
---
--- After its own attack (melee or ranged; counterattacks do not count; for double attacks only the first hit) hits an enemy:
---   per > 0: the target also takes per x own stack size damage of the school (scaled by the target's school reduction);
---   dotPct > 0: at the start of each of the next dotTurns rounds it takes dotPct% of this attack's damage as damage over time (Dark, settled by the battle-wide h6Dot);
---   spell: applies a status spell (level 3, lasting turns rounds).
--- If once is true: works only the first time it hits a given enemy stack (round 351, Shadow Panther "Crippling Wound").
--- dotSrc: name of the damage-over-time source (decides the school, see h6Dot; default dark = Dark, bleed = no school).
--- Parameters: per, school, dotPct, dotTurns, dotSrc, spell, turns, ranged (only when shooting), once, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.isCounter or (payload.attackIndex or 0) > 0 then return end
	if self.ranged and not payload.ranged then return end
	for _, t in ipairs(payload.targets or {}) do
		local target = t.unit
		if target and L.real(target) and battle:isHostile(unit, target) then
			if self.once then
				local key = "h6Once:" .. tostring(unit:unitID())
				if L.markValue(target, key) then break end
				L.setMark(server, battle, target, key, 1)
			end
			if (self.per or 0) > 0 then
				local amount = math.floor(self.per * unit:getCount() * (100 - L.schoolReduction(target, self.school)) / 100)
				if amount > 0 then L.hit(server, battle, target, amount, self.animation, self.sound) end
			end
			if (self.dotPct or 0) > 0 and (t.damage or 0) > 0 and target:isAlive() then
				L.addDot(server, battle, target, (self.dotSrc or "dark") .. tostring(unit:getSide()), math.max(1, math.floor(t.damage * self.dotPct / 100)), self.dotTurns or 2)
			end
			if self.spell and target:isAlive() then
				local sp = L.spell(self.spell)
				if sp then server:applySpellEffects(battle, unit, sp, { target }, 3, self.turns or 1, false) end
			end
			break
		end
	end
end

return Script
