--- Seal of Might (H6 Memorial Sanctum, Inferno Warcry): targets demons gated in by its own side with H6 Gating (mark h6RcGated).
--- Original: demons that came through the gate stay after battle to replace fallen demons, up to cap health, never above the pre-battle count.
--- How it works: at once, whole creatures worth min(total health, cap, health the source stack has lost) are taken from the summoned stack and returned to the source stack (resurrected, permanent); the summons shrink accordingly (and vanish if all are taken).
--- Cannot be cast while the source stack has lost nothing. Parameters: cap (4 original values), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function ring(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

function Script:source(battle, u)
	local id = (L.markValue(u, "h6RcGated") or 0) - 1
	if id < 0 then return nil end
	for _, t in ipairs(battle:getUnitsIf(function(x) return x:unitID() == id and x:isAlive() end)) do return t end
	return nil
end

--- How much health can be returned this time, and the source stack
function Script:amount(mechanics, u)
	local tpl = self:source(mechanics:getBattle(), u)
	if tpl == nil then return 0, nil end
	local lost = L.initialHealth(tpl) - tpl:getAvailableHealth()
	return math.max(0, math.min(u:getAvailableHealth(), math.floor(M.value(mechanics, self.cap)), lost)), tpl
end

function Script:isValidTarget(mechanics, unit)
	if not M.real(unit) or unit:getSide() ~= mechanics:getCasterSide() then return false end
	return (self:amount(mechanics, unit)) >= unit:getMaxHealth()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local amt, tpl = self:amount(mechanics, u)
	local n = math.floor(amt / math.max(1, u:getMaxHealth()))
	if tpl == nil or n <= 0 then return end
	if Proxy.trial(server) then Proxy.buff(server, battle, tpl, { type = "GENERAL_DAMAGE_PREMY", val = 10, turns = 2 }); return end
	L.show(server, battle, { u, tpl }, self.animation, self.sound)
	server:healUnit(battle, tpl, n * tpl:getMaxHealth(), ring(tpl) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	if n >= u:getCount() then
		server:removeUnit(battle, u)
	else
		local st = u:copy()
		st:damage(n * u:getMaxHealth())
		server:changeUnit(battle, st)
	end
	L.log(server, battle, "H6_MM_STATUS_H6C", 6, { L.name(tpl) }, { n })
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
