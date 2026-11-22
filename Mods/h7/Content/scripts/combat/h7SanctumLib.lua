--- Helpers shared by the H7 Memorial Sanctum ultimate scripts (only loaded with require("heroes-memorial.h7:combat/h7SanctumLib"), not registered as a script).
--- Counter marks: hidden bonus H7_SANCTUM_H7C, val = id x 100000 + count.
--- The engine removes bonuses by "type, value, source" (ignoring the stacking group), so each kind of mark has its own id and distinct values,
--- so removing one kind never removes another by mistake (nor clashes with H7_ATK_MARK_H7C shared by other batches).

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}

M.TYPE = "H7_SANCTUM_H7C"
local BASE = 100000

local function list(unit, code)
	return unit:getBonuses({ type = M.TYPE }):filter(function(b)
		return math.floor(b:getVal() / BASE) == code
	end)
end

--- Count of a mark; nil without the mark
function M.get(unit, code)
	local l = list(unit, code)
	if l:size() == 0 then return nil end
	return l:getBonus(1):getVal() % BASE
end

function M.clear(server, battle, unit, code)
	local l = list(unit, code)
	if l:size() > 0 then Proxy.removeExact(server, battle, unit, l) end
end

--- turns = nil: whole battle; otherwise N rounds (1 = until the end of this round)
function M.set(server, battle, unit, code, n, turns)
	M.clear(server, battle, unit, code)
	local d = {
		type = M.TYPE, val = code * BASE + n, hidden = true,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}
	if turns then d.duration = ENUM.BonusDuration.nTurns; d.turns = turns else d.duration = ENUM.BonusDuration.oneBattle end
	server:addUnitBonus(battle, unit, d, true)
end

return M
