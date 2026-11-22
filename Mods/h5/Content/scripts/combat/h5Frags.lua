local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Kill record for H5 Holy Retribution: each time the stack kills creatures with an attack (retaliation included), "level of the killed creature x number" is added to
--- its own hidden bonus H5_FRAGS_H5C (this battle). Attached to all stacks by the creatures casting Holy Retribution (Seraph) with a battle-wide hidden bonus.

local FRAGS = "H5_FRAGS_H5C"

function Script:onAfterAttack(server, battle, unit, other, payload)
	local add = 0
	for _, t in ipairs(payload.targets or {}) do
		if t.killed and t.killed > 0 and t.unit then
			local lvl = math.max(1, t.unit:creatureLevel())
			add = add + lvl * t.killed
		end
	end
	if add <= 0 then return end
	local cur = unit:getBonusesValue({ type = FRAGS })
	server:removeUnitBonuses(battle, unit, unit:getBonuses({ type = FRAGS }))
	server:addUnitBonus(battle, unit, {
		type = FRAGS, val = cur + add, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = "h5Frags", hidden = true
	}, false)
end

return Script
