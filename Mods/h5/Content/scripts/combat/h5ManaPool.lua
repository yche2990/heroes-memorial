local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mana pool of H5 spellcasting creatures: at battle start the cast limit is topped up to "mana / cheapest spell cost".
--- The creature's own CASTS is based on its own mana; creature experience adds mana (H5_MANA_H5C), and the extra mana is converted into casts here,
--- while whether and which spell can really be cast is decided by h5ManaGate on the spell from the remaining mana (spells/h5ManaGate.lua).

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() then return end
	local mana = unit:getBonusesValue({ type = "H5_MANA_H5C" })
	local cheapest = unit:getBonusesValue({ type = "H5_MANA_MIN_H5C" })
	if mana <= 0 or cheapest <= 0 then return end
	local want = math.floor(mana / cheapest)
	local have = unit:getBonusesValue({ type = "CASTS" })
	if want > have then
		server:addUnitBonus(battle, unit, {
			type = "CASTS", val = want - have, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.creatureAbility, sourceID = unit:getCreature():getJsonKey(),
			stacking = "h5ManaCasts", hidden = true
		}, false)
	end
end

return Script
