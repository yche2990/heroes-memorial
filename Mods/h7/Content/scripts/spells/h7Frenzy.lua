local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local L = require("combat/h7SfLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Frenzy (H7): the target stack immediately makes one melee attack on a random adjacent stack (friend or foe), not using its own action.
--- Its Attack changes by slope[mastery] x Magic - 50 for this attack (H7 original); Expert (with "Fire Understanding III") +20 more and the target's enemies are preferred.
--- VCMI cannot let a stack strike during someone else's turn, so this hit uses the engine's normal attack formula (stack size x random damage x attack/defense factor),
--- triggers no attack abilities and cannot be counterattacked.
--- Parameters: slope (4 numbers, by mastery), bonus (extra Attack at Expert), expertLevel (level from which enemies are preferred, default 3)

local function rollBase(server, unit)
	local n = unit:getCount()
	local lo, hi = unit:getMinDamage(false), unit:getMaxDamage(false)
	if hi < lo then hi = lo end
	if n <= 0 then return 0 end
	if n <= 10 then
		local s = 0
		for _ = 1, n do s = s + server:rngInt(lo, hi) end
		return s
	end
	local s = 0
	for _ = 1, 10 do s = s + server:rngInt(lo, hi) end
	return math.floor(s * n / 10)
end

local function candidates(battle, unit)
	return battle:getUnitsIf(function(u)
		return u:unitID() ~= unit:unitID() and u:isAlive() and not u:isGhost() and not u:isTurret()
			and not u:isInvincible() and L.adjacent(unit, u)
	end)
end

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if not unit:isAlive() or unit:isTurret() then return false end
	if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	if unit:getMinDamage(false) <= 0 and unit:getMaxDamage(false) <= 0 then return false end
	return #candidates(mechanics:getBattle(), unit) > 0
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local lvl, sp = Lib.level(mechanics), Lib.power(mechanics)
	local slope = self.slope or { 1, 2, 3, 6 }
	local mod = math.floor((slope[lvl + 1] or slope[#slope]) * sp) - 50
	local expert = lvl >= (self.expertLevel or 3)
	if expert then mod = mod + (self.bonus or 20) end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local list = candidates(battle, unit)
			if expert then
				local hostile = {}
				for _, u in ipairs(list) do
					if u:getSide() ~= unit:getSide() then hostile[#hostile + 1] = u end
				end
				if #hostile > 0 then list = hostile end
			end
			if #list > 0 then
				local victim = list[server:rngInt(1, #list)]
				local base = rollBase(server, unit)
				local diff = unit:getAttack(false) + mod - victim:getDefense(false)
				local factor
				if diff > 0 then
					factor = 1 + 0.05 * math.min(diff, 60)
				else
					factor = 1 - 0.025 * math.min(-diff, 28)
				end
				local dmg = math.max(1, math.floor(base * factor))
				if server:describeChanges() then
					server:showBattleAnimation(battle, { { unit = victim } }, "h7/fx/sfFrenzy", "", 0.8, true)
				end
				server:damageUnit(battle, victim, dmg)
			end
		end
	end
end

--- Round 301: newer engines call this every time a target is chosen; returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Frenzy (H7): the target at once attacks an adjacent stack
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorCharm" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: the stack that gets hit is chosen at random when cast, so a number is shown only when there is exactly one candidate (same formula as apply, random damage averaged);
--- returns 0 when there are several candidates
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local lvl, sp = Lib.level(mechanics), Lib.power(mechanics)
		local slope = self.slope or { 1, 2, 3, 6 }
		local mod = math.floor((slope[lvl + 1] or slope[#slope]) * sp) - 50
		local expert = lvl >= (self.expertLevel or 3)
		if expert then mod = mod + (self.bonus or 20) end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local unit = dest.unit
			if unit and unit:isAlive() then
				local list = candidates(battle, unit)
				if expert then
					local hostile = {}
					for _, u in ipairs(list) do
						if u:getSide() ~= unit:getSide() then hostile[#hostile + 1] = u end
					end
					if #hostile > 0 then list = hostile end
				end
				if #list ~= 1 then return zero end
				local victim = list[1]
				local n = unit:getCount()
				local lo, hi = unit:getMinDamage(false), unit:getMaxDamage(false)
				if hi < lo then hi = lo end
				local base = math.floor(n * (lo + hi) / 2)
				local diff = unit:getAttack(false) + mod - victim:getDefense(false)
				local factor
				if diff > 0 then
					factor = 1 + 0.05 * math.min(diff, 60)
				else
					factor = 1 - 0.025 * math.min(-diff, 28)
				end
				local copy = victim:copy()
				local hp, cnt = copy:getAvailableHealth(), copy:getCount()
				copy:damage(math.max(1, math.floor(base * factor)))
				out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
				out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
