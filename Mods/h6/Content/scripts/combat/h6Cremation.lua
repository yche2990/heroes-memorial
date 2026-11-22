local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cremation (H6 Fire Elemental): when the whole stack dies, all surrounding stacks (friend or foe) take per x stack size at battle start Fire damage (scaled by Fire reduction).
--- If once is true it explodes only once per battle (no second explosion after a Phoenix rebirth). Parameters: per, once, animation, sound

local KEY = "h6CremationCount"

function Script:onBattleStart(server, battle, unit)
	if unit:isAlive() then L.setMark(server, battle, unit, KEY, unit:getCount()) end
end

function Script:onDeath(server, battle, unit)
	if self.once then
		if L.markValue(unit, KEY .. "Done") then return end
		L.setMark(server, battle, unit, KEY .. "Done", 1)
	end
	-- Review B3 (2026-11-08): stacks summoned mid-battle (Summon Fire Elemental) do not get the battle start event and have no mark; a summon's base count is its count when summoned
	local n = L.markValue(unit, KEY) or math.max(1, unit:getBaseAmount())
	local list = battle:getUnitsIf(function(u) return L.real(u) and u:unitID() ~= unit:unitID() and L.adjacent(unit, u) end)
	for _, u in ipairs(list) do
		local amount = math.floor((self.per or 5) * n * (100 - L.schoolReduction(u, "fire")) / 100)
		if amount > 0 then L.hit(server, battle, u, amount, self.animation, self.sound) end
	end
	if #list > 0 and server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
