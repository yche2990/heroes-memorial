--- H6 memorial Gating I-IV (Inferno racial ability; special spells from the Tears of Ashan Gating skill, no Spell Book needed).
--- First choose a friendly stack of H6 Inferno creatures (H6_GATING_H6C; Yu's decision: H6 creatures only; level I can choose levels 1-3, II levels 1-6, III/IV levels 1-7), then a free hex.
--- Count = own total health at battle start x pct% / health per creature of that kind (at least 1). Levels I-III place a gate on the free hex (h6RcInfernalGate; the gate's count is its health,
--- = 30% of the total summoned health) that opens at the start of the next round if it still stands (combat/h6RcGateOpen); if the gate is destroyed the summoning fails; level IV summons at once.
--- The summons remember their source stack; when the source stack is wiped out, they return to the Abyss (combat/h6RcGatedLink).
--- Can only be cast with the charge bar at tier x 100, which it uses up. Parameters: tier, pct (%), gate (gate creature), animation, sound, summonFx, summonSound, unsummonFx, unsummonSound
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local R = require("lib/h6RcLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local MAXLV = { 3, 6, 7, 7 }

function Script:adjustTargetTypes(mechanics, types)
	if #types == 0 then return types end
	if types[1] ~= ENUM.AimType.creature then return {} end
	if #types == 1 then return { ENUM.AimType.creature, ENUM.AimType.location } end
	if types[2] ~= ENUM.AimType.location then return {} end
	return types
end

function Script:template(mechanics, u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() or u:getSide() ~= mechanics:getCasterSide() then return false end
	if not R.has(u, "H6_GATING_H6C") then return false end   -- Yu's decision: H6 Inferno creatures only (to avoid doubling with Tears of Ashan Gating)
	local lv = u:creatureLevel()
	return lv >= 1 and lv <= MAXLV[self.tier or 1]
end

function Script:startHealth(battle, side)
	local total = 0
	for _, u in ipairs(battle:getUnitsIf(function(u) return u:getSide() == side and not u:isTurret() end)) do
		if not u:copy():isSummoned() and not u:isClone() and not R.has(u, "SIEGE_WEAPON") then total = total + L.initialHealth(u) end
	end
	return total
end

function Script:amount(mechanics, u)
	local hp = math.max(1, u:getMaxHealth())
	return math.max(1, math.floor(self:startHealth(mechanics:getBattle(), mechanics:getCasterSide()) * (self.pct or 3.43) / 100 / hp + 0.5))
end

function Script:applicableGeneral(mechanics, problem)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	if R.gauge(battle, side, "gate") < (self.tier or 1) * 100
	   or #battle:getUnitsIf(function(u) return self:template(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	if #target == 0 then return false end
	local u = target[1].unit
	if not self:template(mechanics, u) then return false end
	if #target == 1 then return true end
	local hex = target[2].hex
	local battle = mechanics:getBattle()
	if hex == nil or not hex:isValid() or not hex:isAvailable() or battle:getUnitByPos(hex, true) ~= nil then return false end
	if (self.tier or 1) >= 4 then
		local ok, acc = pcall(function() return battle:isAccessibleForNewUnit(hex, u:getCreature(), mechanics:getCasterSide()) end)
		return ok and acc
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local battle = mechanics:getBattle()
	if #aimPoint == 0 then return {} end
	local first = aimPoint[1]
	local u = first.unit or (first.hex and battle:getUnitByPos(first.hex, true))
	local result = { { unit = u, hex = first.hex } }
	if #aimPoint >= 2 then result[2] = { hex = aimPoint[2].hex } end
	return result
end
function Script:filterTarget(mechanics, target) return target end

function Script:apply(mechanics, server, target)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	if #target < 2 then return end
	local tpl, hex = target[1].unit, target[2].hex
	if tpl == nil or not tpl:isAlive() or hex == nil then return end
	local tier = self.tier or 1
	local count = self:amount(mechanics, tpl)
	if Proxy.trial(server) then Proxy.creditSide(server, battle, side, Proxy.value(tpl) * count * (tier >= 4 and 1 or 0.6)); return end
	R.setGauge(server, battle, side, "gate", R.gauge(battle, side, "gate") - tier * 100)
	if tier >= 4 then
		R.summon(server, battle, tpl, count, hex, self.summonFx, self.summonSound, self.unsummonFx, self.unsummonSound)
	else
		local gcr = LIBRARY:getCreatureByName(self.gate or "heroes-memorial.h6:h6RcInfernalGate")
		if gcr == nil then return end
		local hp = math.max(1, math.floor(count * tpl:getMaxHealth() * 0.3))
		local g = server:addUnit(battle, { count = hp, type = gcr, side = side, position = hex, summoned = true })
		if g == nil then g = battle:getUnitByPos(hex, true) end
		if g == nil then return end
		L.setMark(server, battle, g, "h6RcGateTpl", tpl:unitID() + 1)
		L.setMark(server, battle, g, "h6RcGateCnt", count)
		if self.animation and server:describeChanges() then
			server:showBattleAnimation(battle, { { unit = g } }, self.animation, self.sound or "", 1.0, true)
		end
	end
	server:refreshBattleUnits(battle)
end

--- Cursor and status bar text while choosing a target: the second step picks a free hex for the Gate (at level IV it summons directly), cursor kadCursorSummon.
--- The second step used to show the Sacrifice cursor and "Select a stack to sacrifice"; now it uses the spell parameter hoverText ("Open the gate here" / "Summon demons here"),
--- hexes where it does not fit show the original "X cannot be placed here"; healthGainTextID added (the summon estimate "+N" is appended when present). The first step uses the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 1 then return nil end
	local spellName = mechanics:getSpell():getNameTextID()
	local text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } } -- without hoverText: Cast %s
	if self.hoverText ~= nil then
		text = { append = { self.hoverText } }
	end
	return {
		cursor = "kadCursorSummon",
		text = text,
		blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } }, -- %s cannot be placed here
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: only level IV summons at once, same formula as apply. amount(source stack) creatures of the same kind (this number is also shown before the free hex is chosen).
--- Levels I-III first place the gate, which opens next round if it still stands; casting summons nothing, returns 0
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	if (self.tier or 1) < 4 then return zero end
	local ok, result = pcall(function()
		local first = spellTarget and spellTarget[1]
		local tpl = first and first.unit
		if not self:template(mechanics, tpl) then return zero end
		local count = self:amount(mechanics, tpl)
		if count <= 0 then return zero end
		return { hpDelta = count * tpl:getMaxHealth(), unitsDelta = count, unitType = tpl:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
