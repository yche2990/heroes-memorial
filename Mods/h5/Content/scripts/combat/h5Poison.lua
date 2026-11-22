local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Poisonous Attack (Cutthroat, Stalker, Flying Manticore), Venom (Venomous Wyvern)
---
--- When an attack hits an enemy (ranged, melee, retaliation), the target is poisoned: for the next turns rounds it takes, at the start of each round,
--- "perCreature x the poisoner's count at that time" damage, ignoring Attack and Defense. Undead, elementals, mechanical and war machines cannot be poisoned.
--- Poisoning again refreshes it with a new dose (the higher damage is kept, rounds restart).
--- Each round is settled by combat/h5PoisonTick on the target (value = damage per round).
--- Parameters: perCreature, turns

local STACK = "h5Poison"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local amount = (self.perCreature or 1) * unit:getCount()
	if amount <= 0 then return end
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		if t and t:isAlive() and not t:isInvincible() and battle:isHostile(unit, t)
			and (entry.damage or 0) > 0 and H5.isLivingH5(t) and not t:isTurret() then
			local old = t:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == STACK end)
			local keep = 0
			for i = 1, old:size() do keep = math.max(keep, old:getBonus(i):getVal()) end
			if old:size() > 0 then server:removeUnitBonuses(battle, t, old) end
			server:addUnitBonus(battle, t, {
				type       = "COMBAT_EVENT_TRIGGER",
				subtype    = "h5PoisonTick",
				val        = math.max(keep, amount),
				duration   = ENUM.BonusDuration.nTurns,
				turns      = (self.turns or 3) + 1,
				sourceType = ENUM.BonusSource.creatureAbility,
				sourceID   = unit:getCreature():getJsonKey(),
				stacking   = STACK,
				icon       = "h5/abilities/poison"
			}, false)
			server:showBattleAnimation(battle, { { unit = t } }, "h5/fx/Characters_hits_poison_hit", "", 0.8, true)
			server:refreshBattleUnits(battle)
		end
	end
end

return Script
