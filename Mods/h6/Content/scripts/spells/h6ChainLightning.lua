local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Chain Lightning (H6 Thunderbird): deals per Air damage to an enemy stack, then jumps to the jumps other enemies nearest the previous target,
--- halving the damage each jump. Scaled by Air and all-spell reduction. Parameters: per, jumps, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	return caster ~= nil and L.real(unit) and not unit:isInvincible() and mechanics:getBattle():isHostile(caster, unit)
end
function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false
end
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local cur = target[1] and target[1].unit
	if caster == nil or cur == nil then return end
	local dmg = self.per or 150
	local seen, total, n = {}, 0, 0
	for k = 0, (self.jumps or 3) do
		seen[cur:unitID()] = true
		n = n + 1
		total = total + (L.hit(server, battle, cur, math.floor(dmg * (100 - L.schoolReduction(cur, "air")) / 100), self.animation, self.sound) or 0)
		dmg = math.floor(dmg / 2)
		if dmg <= 0 then break end
		local best, bd = nil, 1000
		for _, u in ipairs(battle:getUnitsIf(function(u) return self:isValidTarget(mechanics, u) and not seen[u:unitID()] end)) do
			local d = L.unitDistance(cur, u)
			if d < bd then best, bd = u, d end
		end
		if best == nil then break end
		cur = best
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 11, { L.name(caster) }, { n, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- For the hover estimate: a copy of L.hit that returns damage, kills (0, 0 when the target cannot be hit or the values are invalid)
local function hcHit(target, amount)
	amount = math.floor(amount or 0)
	if target == nil or not target:isAlive() or target:isGhost() or target:isInvincible() or amount <= 0 then return 0, 0 end
	local copy = target:copy()
	local hp, cnt = copy:getAvailableHealth(), copy:getCount()
	copy:damage(amount)
	return hp - copy:getAvailableHealth(), cnt - copy:getCount()
end

--- Hover estimate: same formula as apply. The first stack takes per, each further jump half as much, jumping to the enemy stack nearest to the previous target,
--- each reduced by air and all-spell reductions; damage and kills of all stacks hit are summed
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local cur = first and first.unit
		if caster == nil or cur == nil then return zero end
		local out = { hpDelta = 0, unitsDelta = 0 }
		local dmg = self.per or 150
		local seen = {}
		for k = 0, (self.jumps or 3) do
			seen[cur:unitID()] = true
			local d, killed = hcHit(cur, math.floor(dmg * (100 - L.schoolReduction(cur, "air")) / 100))
			out.hpDelta, out.unitsDelta = out.hpDelta - d, out.unitsDelta - killed
			dmg = math.floor(dmg / 2)
			if dmg <= 0 then break end
			local best, bd = nil, 1000
			for _, u in ipairs(battle:getUnitsIf(function(u) return self:isValidTarget(mechanics, u) and not seen[u:unitID()] end)) do
				local dist = L.unitDistance(cur, u)
				if dist < bd then best, bd = u, dist end
			end
			if best == nil then break end
			cur = best
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
