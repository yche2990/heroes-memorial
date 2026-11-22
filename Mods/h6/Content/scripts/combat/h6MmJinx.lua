--- Jinx (H6 Memorial Sanctum, Sanctuary; ability of the pet Shadow Panther cub): at battle start each enemy stack randomly gets one of Chilled, Frozen, Soaked or Dazed
--- (original H6 statuses, applied as spells, immunity follows each status's own rules). After learning it, all of the hero's stacks carry this hidden script;
--- the first stack to trigger puts the statuses on all enemies, later ones skip when they see the enemies already marked.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local STATUS = { "h6Chilled", "h6Frozen", "h6Soaked", "h6Dazed" }

function Script:onBattleStart(server, battle, unit, other, payload)
	if not server:describeChanges() then return end
	local foes = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and battle:isHostile(unit, u)
			and not u:hasBonuses({ type = "SIEGE_WEAPON" }) and L.markValue(u, "h6MmJinxed") == nil
	end)
	if #foes == 0 then return end
	for _, u in ipairs(foes) do
		L.setMark(server, battle, u, "h6MmJinxed", 1)
		local sp = LIBRARY:getSpellByName("kad-mechanics:" .. STATUS[server:rngInt(1, #STATUS)])
		if sp then server:castSpell(battle, unit, sp, { u }, 0) end
	end
	server:refreshBattleUnits(battle)
end

return Script
