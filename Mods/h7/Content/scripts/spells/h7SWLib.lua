--- Small helpers shared by spell batch SW (Water + Teleport, Dispel) of H7 Creatures and Magic (heroes-memorial.h7).
--- Only used via require("heroes-memorial.h7:spells/h7SWLib"), not registered as a script.

local M = {}

M.MOD = "heroes-memorial.h7"

function M.spell(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(M.MOD .. ":" .. name) end)
	return s
end

function M.creature(name)
	local c = nil
	pcall(function() c = LIBRARY:getCreatureByName(M.MOD .. ":" .. name) end)
	return c
end

--- Safe bonus lookup (no error when the type is not registered)
function M.has(unit, t)
	local ok, r = pcall(function() return unit:hasBonuses({ type = t }) end)
	return ok and r
end

function M.value(unit, t)
	local ok, r = pcall(function() return unit:getBonusesValue({ type = t }) end)
	return (ok and r) or 0
end

--- Hex distance
function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

--- shortest distance from any hex of a unit to hex
function M.unitDistance(unit, hex)
	local best = 99
	local hs = unit:getHexes()
	for i = 1, hs:size() do best = math.min(best, M.hexDistance(hs:at(i), hex)) end
	return best
end

function M.neighbours(hex)
	return { hex:copyToEast(), hex:copyToWest(), hex:copyToNorthEast(), hex:copyToNorthWest(),
		hex:copyToSouthEast(), hex:copyToSouthWest() }
end

--- Hex 110 (row 6, column 8): full-field effects (820x676 image) are played aligned to this hex's top edge, so the image's top-left lands exactly on the battlefield's top-left.
--- BattleHex cannot be constructed directly; walk there from any hex.
function M.fieldHex(hex)
	local h = hex
	for _ = 1, 40 do
		if h == nil or not h:isValid() then return nil end
		local x, y = h:getX(), h:getY()
		if y < 6 then h = (x < 8) and h:copyToSouthEast() or h:copyToSouthWest()
		elseif y > 6 then h = (x < 8) and h:copyToNorthEast() or h:copyToNorthWest()
		elseif x < 8 then h = h:copyToEast()
		elseif x > 8 then h = h:copyToWest()
		else return h end
	end
	return nil
end

--- Plays a full-field effect (deferred), followed by refreshBattleUnits so it finishes on its own. ref is any hex.
function M.fieldAnim(server, battle, ref, anim, sound)
	if ref == nil or not server:describeChanges() then return false end
	local h = M.fieldHex(ref)
	if h == nil then return false end
	server:showBattleAnimation(battle, { { hex = h } }, anim, sound or "", 1.0, true)
	server:refreshBattleUnits(battle)
	return true
end

--- Any hex on the battlefield (the position of any stack)
function M.anyHex(battle)
	local list = battle:getUnitsIf(function(u) return u:isAlive() end)
	if #list > 0 then return list[1]:getPosition() end
	return nil
end

--- H7 "Magic" and mastery (the same set as heroes-memorial.h5: hero casts = Spell Power)
local H5 = require("heroes-memorial:spells/h5SpellLib")
M.power = H5.power
M.level = H5.level

function M.pick(arr, lvl)
	if arr == nil then return 0 end
	return arr[lvl + 1] or arr[#arr] or 0
end

return M
