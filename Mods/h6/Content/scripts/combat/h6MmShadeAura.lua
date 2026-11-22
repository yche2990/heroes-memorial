--- Entangling Shade (H6 Memorial Sanctum, Dungeon) illusion aura (battle-level hidden script, added once by spells/h6MmShade): enemies adjacent to the illusion deal -N% damage
--- (N = value of the "Entangling Shade" status on the illusion). Recalculated by current positions at battle start, at the start of each round, and after every move and action; removed when no longer adjacent or the illusion is gone.
--- Stacking group h6MmShadeAura<illusion id>; several illusions count separately.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local PREFIX = "h6MmShadeAura"

local function shades(battle)
	local out = {}
	for _, s in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() end)) do
		local list = s:getBonuses({ type = "H6_MM_SHADE_H6C" }):filter(function(b) return b:getStacking() == "h6MmShade" end)
		if list:size() > 0 then out[#out + 1] = { unit = s, val = list:getBonus(1):getVal() } end
	end
	return out
end

function Script:refresh(server, battle)
	local want = {}
	local list = shades(battle)
	for _, sh in ipairs(list) do
		local key = PREFIX .. tostring(sh.unit:unitID())
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() and battle:isHostile(sh.unit, x) end)) do
			if L.adjacent(sh.unit, u) then want[u:unitID() .. "|" .. key] = sh.val end
		end
	end
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() end)) do
		local have = u:getBonuses({ type = "GENERAL_DAMAGE_PREMY" }):filter(function(b) return string.sub(b:getStacking() or "", 1, #PREFIX) == PREFIX end)
		local seen = {}
		for i = 1, have:size() do
			local key = have:getBonus(i):getStacking()
			seen[key] = true
			if want[u:unitID() .. "|" .. key] == nil then
				L.removeByStacking(server, battle, u, "GENERAL_DAMAGE_PREMY", key)
				L.removeByStacking(server, battle, u, "H6_MM_SHADED_H6C", key)
			end
		end
		for _, sh in ipairs(list) do
			local key = PREFIX .. tostring(sh.unit:unitID())
			local v = want[u:unitID() .. "|" .. key]
			if v and not seen[key] then
				server:addUnitBonus(battle, u, { type = "GENERAL_DAMAGE_PREMY", val = -v, duration = ENUM.BonusDuration.oneBattle,
					sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = key, hidden = true }, false)
				server:addUnitBonus(battle, u, { type = "H6_MM_SHADED_H6C", val = v, duration = ENUM.BonusDuration.oneBattle,
					sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = key, icon = "h6/abilities/mm_StalkingShade" }, false)
			end
		end
	end
end

function Script:onBattleStart(server, battle) self:refresh(server, battle) end
function Script:onRoundStart(server, battle) self:refresh(server, battle) end
function Script:onActionFinished(server, battle) self:refresh(server, battle) end
function Script:onAfterMove(server, battle) self:refresh(server, battle) end
function Script:onDeath(server, battle) self:refresh(server, battle) end

return Script
