local Base = require("combat/combatScript")
local C = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Invisibility, revealing (H5 Shadow Mistress, Stalker): the invisibility spell attaches this script with attachCombatScript, same duration as the invisibility.
--- At the start of a round and after its own move, if an enemy is adjacent it is revealed (all effects of the invisibility spell removed), with a reveal effect and a battle log line.
--- After its own attack it ends naturally through the spell effect's duration condition (until it attacks).
--- Parameters: spell (full name of the invisibility spell), mark (bonus name for the battle log, value description 1 = revealed by approaching enemy)

function Script:reveal(server, battle, unit)
	if not unit:isAlive() then return end
	local spell = LIBRARY:getSpellByName(self.spell)
	if spell == nil then return end
	local key = spell:getJsonKey()
	local bonuses = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		-- The source id may carry a "spell." prefix or mod name, so it is matched by containment
		local id = tostring(b:getSourceID())
		return id == key or string.find(id, key, 1, true) ~= nil or string.find(id, (key:match(":(.+)$") or key), 1, true) ~= nil
	end)
	if bonuses:size() == 0 then return end
	local side = unit:getSide()
	local enemies = C.adjacentUnits(battle, unit, function(o) return battle:isHostile(unit, o) and not o:isTurret() end)
	if #enemies == 0 then return end
	server:removeUnitBonuses(battle, unit, bonuses)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus." .. self.mark .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
	})
end

function Script:onRoundStart(server, battle, unit) self:reveal(server, battle, unit) end
function Script:onAfterMove(server, battle, unit) self:reveal(server, battle, unit) end

return Script
