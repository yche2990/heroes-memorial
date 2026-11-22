local Base = require("combat/combatScript")
local H5R = require("combat/h5Common")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Spectre: Mana Drain
---
--- Original: when attacking an enemy stack it drains its mana to restore its own health, even resurrecting. H5 creature casting uses the stack's own mana,
--- in the collection creature casting uses casts (CASTS), so: when it actively attacks (not retaliation) an enemy that casts spells (with casts left),
--- that enemy loses one cast and it restores val% (default 25%, approximating "mana into health"; original value unknown) of this attack's damage as health, can resurrect.
---
--- Parameter: val

local ANIM = "h5/fx/Characters_Creatures_Necropolis_Ghosts2_idle00"  -- Original ManaDrain.(SpellVisual)

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.isCounter or (payload.attackIndex or 0) > 0 then return end
	local entry = payload.targets and payload.targets[1]
	local t = entry and entry.unit
	if t == nil or not battle:isHostile(unit, t) then return end
	if L.value(t, { type = "CASTS" }) <= 0 then return end
	if not t:hasBonuses({ type = "SPELLCASTER" }) and not t:hasBonuses({ type = "ENCHANTER" }) then return end

	if t:isAlive() then
		server:addUnitBonus(battle, t, {
			type = "CASTS", val = -1, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			hidden = true   -- Round 375: stacking group h5ManaDrained removed (the engine keeps only one per stacking group, so however many drains it lost only 1 cast)
		}, true)
	end
	local dealt = entry.damage or 0
	local heal = math.floor(dealt * (self.val or 25) / 100)
	if heal <= 0 then return end
	local amt, lvl = H5R.reviveHeal(unit, heal)
	local healed = amt > 0 and server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent) or 0
	server:showBattleAnimation(battle, { { unit = unit } }, ANIM, "", 0.6, true)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus.H5_MANADRAIN_H5C.description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()), t:getCreature():getNameTextID(math.max(1, t:getCount())) },
		replaceNumbers = { healed or heal }
	})
end

return Script
