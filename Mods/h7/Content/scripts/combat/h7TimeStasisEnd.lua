local Base = require("combat/combatScript")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- End of Time Stasis (H7) (added to the battlefield by spells/h7TimeStasis): at the start of each round, the first stack to trigger puts all stacks in stasis
--- (ghost state, mark h7Stasis) back on their old hexes, or on the nearest free hex if the old one is blocked. They act as usual afterwards.
--- Parameter: animation (played when put back)

local MARK = "h7Stasis"

function Script:landingHex(battle, unit, hexes, home)
	if home ~= nil and battle:isAccessibleForUnit(unit, home) and battle:getUnitByPos(home, true) == nil then return home end
	local best, bestD = nil, 1000
	for _, hex in pairs(hexes) do
		if hex:isAvailable() and battle:isAccessibleForUnit(unit, hex) and battle:getUnitByPos(hex, true) == nil then
			local d = home and E.hexDistance(hex, home) or 0
			if d < bestD then best, bestD = hex, d end
		end
	end
	return best
end

function Script:onRoundStart(server, battle, unit, other, payload)
	local frozen = battle:getUnitsIf(function(u)
		return u:isGhost() and u:isAlive() and E.markVal(u, MARK) ~= nil
	end)
	if #frozen == 0 then return end
	local hexes = E.hexTable(battle)
	local back = {}
	for _, u in ipairs(frozen) do
		local idx = (E.markVal(u, MARK) or 0) - 1
		E.clearMark(server, battle, u, MARK)
		local dest = self:landingHex(battle, u, hexes, hexes[idx])
		if dest == nil then dest = battle:getAvailableHex(u:getCreature(), u:getSide(), hexes[idx]) end
		-- H7 audit B7: with a crowded battlefield and no free hex, getAvailableHex returns an invalid hex (not nil): it stays in stasis, the mark is put back, and it tries again next round
		if dest == nil or not dest:isValid() then
			E.setMark(server, battle, u, MARK, idx + 1, nil)
		else
		local state = u:copy()
		state:setGhost(false)
		state:setPosition(dest)
		server:changeUnit(battle, state)
		-- Round 353d: when put elsewhere because the old hex is blocked, the client image stays at the old place, so a teleport is sent to make it follow
		if hexes[idx] == nil or E.hexIndex(dest) ~= idx then
			pcall(function() server:moveUnit(battle, u, dest, true) end)
		end
		back[#back + 1] = u
		end
	end
	server:refreshBattleUnits(battle)
	for _, u in ipairs(back) do
		server:showBattleAnimation(battle, { { unit = u } }, self.animation or "h7/fx/h7eTimeStasis", "h7/spell_time_stasis_tick.ogg", 1.0, true)
		server:refreshBattleUnits(battle)
	end
end

return Script
