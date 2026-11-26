--- Entangling Shade (H6 Memorial Sanctum, Dungeon Might): places an illusion next to the targeted friendly stack: a summoned stack of the same creature with 15% of the original's count (15% of total health, at least 1),
--- dealing -99% damage and not counterattacking; enemies adjacent to it deal -aura% damage (combat/h6MmShadeAura on the battlefield); the illusion vanishes when the original stack is wiped out (combat/h6MmShadeLink on the original).
--- The original "adjacent enemies cannot use abilities" cannot be done. Parameters: hp (percentage of health left), aura, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not M.real(unit) or unit:getSide() ~= mechanics:getCasterSide() or unit:isClone() or unit:copy():isSummoned() then return false end
	return self:spot(mechanics:getBattle(), unit) ~= nil
end
function Script:isReceptive(mechanics, unit) return true end

--- Free hexes next to the original stack (where the illusion fits)
function Script:spot(battle, unit)
	local cr = unit:getCreature()
	local around = unit:getSurroundingHexes()
	for i = 1, around:size() do
		local h = around:at(i)
		if h:isValid() and h:isAvailable() and battle:getUnitByPos(h, true) == nil then
			local ok, acc = pcall(function() return battle:isAccessibleForNewUnit(h, cr, unit:getSide()) end)
			if ok and acc then return h end
		end
	end
	return nil
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	if Proxy.trial(server) then
		Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 15, turns = 2 })
		return
	end
	local hex = self:spot(battle, u)
	if hex == nil then return end
	local cr = u:getCreature()
	local keep = self.hp or 15
	local shade = server:addUnit(battle, { count = math.max(1, math.floor(u:getCount() * keep / 100 + 0.5)), type = cr, side = u:getSide(), position = hex, summoned = true })
	if shade == nil then shade = battle:getUnitByPos(hex, true) end
	if shade == nil then return end
	local function add(d) M.addOther(server, battle, shade, d) end
	add({ type = "GENERAL_DAMAGE_PREMY", val = -99, hidden = true, stacking = "h6MmShadeDmg" })
	add({ type = "NO_RETALIATION", val = 0, hidden = true, stacking = "h6MmShadeNoRet" })
	add({ type = "H6_MM_SHADE_H6C", val = self.aura or 30, stacking = "h6MmShade", icon = "h6/abilities/mm_StalkingShade" })
	M.addOther(server, battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmShadeLink", val = shade:unitID(), hidden = true,
		stacking = "h6MmShadeLink" .. tostring(shade:unitID()) })
	server:addBattleBonus(battle, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmShadeAura", val = 0, duration = "ONE_BATTLE",
		sourceType = "OTHER", hidden = true, stacking = "h6MmShadeAura" })
	L.show(server, battle, { shade }, self.animation, self.sound)
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply. If there is a free hex next to it, an illusion of the same creature appears, count max(1, original stack size x hp% rounded)
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local u = first and first.unit
		if u == nil or not u:isAlive() then return zero end
		if self:spot(mechanics:getBattle(), u) == nil then return zero end
		local cr = u:getCreature()
		local n = math.max(1, math.floor(u:getCount() * (self.hp or 15) / 100 + 0.5))
		return { hpDelta = n * u:getMaxHealth(), unitsDelta = n, unitType = cr }
	end)
	if ok and result then return result end
	return zero
end

return Script
