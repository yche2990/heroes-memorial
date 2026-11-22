--- AI value hint (2026-11-08, AI skill fixes): a spell effect that only works in the AI simulation (Proxy.trial); real casts do nothing.
---
--- Purpose: when the AI cannot value a spell's real effect (GENERAL_DAMAGE_PREMY, custom marks, summons, repositioning...), or values it far below the boss's own
--- normal attack (a boss hit is worth hundreds to thousands of points), the AI always just attacks and never uses the ability. With this effect written into the same spell as the real effects,
--- the simulation reports an equivalent value the AI understands (proxy damage on enemies / native bonuses) by the rules below, so the AI casts it at the right moment.
--- Effects of a spell run in name order; this effect's name starts with "0" (e.g. "0aiHint"), so it runs before dispel and the like and sees the situation before the cast.
---
--- Units: value = value per creature x health fraction (as lib/kadAiProxy). "Value of one normal attack" = h6SpLib.attackValue (expected damage of one normal attack on the enemy most worth hitting,
--- converted to value, no dice). Finally Proxy.credit books it on the enemy stack with the most health on the casting side's opposing side (at most half its health).
---
--- Parameters:
---   mode   "allies" (default): affected allies (the casting side's stacks on the target hex and in the spell range); value = ratio x sum of one normal attack's value of each ally;
---                            optionally proxyBonus (cannot be called bonus: the engine parses bonus in spell effects as a bonus table): gives each of these allies one native bonus (an equivalent the engine understands, e.g. PRIMARY_SKILL attack).
---          "dispel": number n of beneficial spells on the target enemy (counted per spell, at most cap); value = ratio x value of one normal attack of the caster x n. 0 if none.
---          "foes": number n of enemy stacks affected (at most cap); value = ratio x value of one normal attack of the caster x n.
---                  center: "target" (the target and enemies within radius hexes of it; radius default 0 = target only), "caster" (within radius hexes of the caster),
---                  "all" (all enemies); small true counts single-hex stacks only; melee true counts non-shooters only;
---                  status: full name of a status spell; stacks immune to it or already under it are not counted; skip: stacks with this bonus type are not counted;
---                  bigFirst true also multiplies by "target value / value of the largest enemy stack" (marks prefer the strongest).
---   ratio (multiplier per share, default 0.5), cap (maximum shares, default 3), proxyBonus ({ type, subtype, val, turns }, only for allies)
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end

--- Only attaches the stacks on the target hexes (the engine gives spell effect scripts only hexes); allies mode keeps only the casting side's stacks, the others keep only the first one (main target),
--- without adding anything else to the "affected stacks"
function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local all = L.unitTarget(mechanics, spellTarget)
	local side = mechanics:getCasterSide()
	local out = {}
	for _, d in ipairs(all) do
		if d.unit ~= nil then
			if (self.mode or "allies") == "allies" then
				if d.unit:getSide() == side then out[#out + 1] = d end
			elseif #out == 0 then
				out[1] = d
			end
		end
	end
	return out
end

local function positiveSpells(u)
	local keys, n = {}, 0
	local list = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	for i = 1, list:size() do
		local k = list:getBonus(i):getSourceID()
		if not keys[k] then
			local sp = LIBRARY:getSpellByName(k)
			if sp ~= nil and sp:isPositive() then keys[k] = true; n = n + 1 end
		end
	end
	return n
end

function Script:countFoes(battle, caster, main)
	local status = self.status and L.spell(self.status) or nil
	local statusKey = status and status:getJsonKey() or nil
	local function ok(u)
		if not Proxy.hostile(battle, caster, u) or u:isInvincible() then return false end
		if self.small and u:getHexes():size() ~= 1 then return false end
		if self.melee and u:isShooter() then return false end
		if self.skip and u:hasBonuses({ type = self.skip }) then return false end
		if statusKey then
			if Proxy.immune(u, { spell = statusKey, negative = true }) then return false end
			if u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b) return b:getSourceID() == statusKey end):size() > 0 then return false end
		end
		return true
	end
	local center = self.center or "target"
	local r = self.radius or 0
	local n = 0
	if center == "all" then
		n = #battle:getUnitsIf(ok)
	elseif center == "caster" then
		n = #battle:getUnitsIf(function(u) return ok(u) and L.unitDistance(caster, u) <= math.max(1, r) end)
	else
		if main == nil or not ok(main) then return 0 end
		n = 1
		if r > 0 then
			n = n + #battle:getUnitsIf(function(u) return u:unitID() ~= main:unitID() and ok(u) and L.unitDistance(main, u) <= r end)
		end
	end
	return n
end

function Script:apply(mechanics, server, target)
	if not Proxy.trial(server) then return end         -- real cast: do nothing
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local mode = self.mode or "allies"
	local ratio = self.ratio or 0.5
	local cap = self.cap or 3
	local value = 0
	if mode == "allies" then
		for _, d in ipairs(target) do
			local a = d.unit
			if a ~= nil and a:isAlive() and not a:isGhost() and a:getSide() == mechanics:getCasterSide() then
				value = value + ratio * S.attackValue(battle, a)
				if self.proxyBonus then
					local b = self.proxyBonus
					Proxy.buff(server, battle, a, { type = b.type, subtype = b.subtype, val = b.val or 0, turns = b.turns or 1 })
				end
			end
		end
	elseif caster ~= nil then
		local main = target[1] and target[1].unit or nil
		local n = 0
		if mode == "dispel" then
			if main ~= nil and Proxy.hostile(battle, caster, main) then n = positiveSpells(main) end
		else
			n = self:countFoes(battle, caster, main)
		end
		value = ratio * S.attackValue(battle, caster) * math.min(n, cap)
		if value > 0 and self.bigFirst and main ~= nil then
			local top = 0
			for _, e in ipairs(battle:getUnitsIf(function(u) return Proxy.hostile(battle, caster, u) end)) do
				top = math.max(top, Proxy.value(e) * e:getCount())
			end
			if top > 0 then value = value * math.min(1, Proxy.value(main) * main:getCount() / top) end
		end
	end
	if value > 0 then S.credit(server, battle, mechanics, value) end
end

return Script
