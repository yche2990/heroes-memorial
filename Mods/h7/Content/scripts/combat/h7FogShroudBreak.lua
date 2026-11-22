local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mist Veil (H7) none/basic/advanced: put on the target by the spell h7FogShroud (heroes-memorial:h5Attach), expiring together with the mist effects.
--- When the target is attacked in melee and takes damage, all effects of the Mist Veil are removed (this script included).
--- Ranged attacks do not hurt it (the damage patch damage/h7FogShroudPatch reduces shots at it to 0); spell damage removes it via the effect's own
--- UNTIL_TAKING_INDIRECT_DAMAGE. The Expert Mist Veil does not carry this script and does not vanish on damage.

local function isFog(bonus)
	if bonus:getSource() ~= ENUM.BonusSource.spellEffect then return false end
	local id = tostring(bonus:getSourceID() or "")
	return string.find(id, "h7FogShroud", 1, true) ~= nil
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or payload == nil or payload.ranged then return end
	local own = self:ownEntry(unit, payload)
	if own == nil or (own.damage or 0) <= 0 then return end
	local list = unit:getBonuses({}):filter(isFog)
	if list:size() > 0 then
		server:removeUnitBonuses(battle, unit, list)
		server:refreshBattleUnits(battle)
	end
end

return Script
