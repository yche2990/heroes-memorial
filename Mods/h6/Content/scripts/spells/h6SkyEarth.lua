local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Sky and Earth, Heaven and Earth Spirits (H6 Dream Walker, Dream Reaver)
---
--- Allies: hasted (status spell sky); non-flying enemies: slowed (status spell earth) and take per x number of casters Earth damage
--- (scaled by Earth and all-spell reduction). Both statuses last turns rounds.
--- If mass is false it is cast on one chosen stack (spell target CREATURE); if true, on all allies and all non-flying enemies (NO_TARGET).
--- Parameters: mass, sky, earth, per, turns, key, animation, sound

function Script:ok(mechanics, caster, u)
	if not L.real(u) then return false end
	if not mechanics:getBattle():isHostile(caster, u) then return true end
	return not u:hasBonuses({ type = "FLYING" }) and not u:isInvincible()
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	if self.mass then return unit:unitID() == caster:unitID() end
	return self:ok(mechanics, caster, unit)
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	if self.mass then return self:applicableGeneral(mechanics, problem) end
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:filterTarget(mechanics, target)
	if self.mass then return target end
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local list = {}
	if self.mass then
		list = battle:getUnitsIf(function(u) return self:ok(mechanics, caster, u) end)
	else
		local u = target[1] and target[1].unit
		if u then list[1] = u end
	end
	local allies, foes = {}, {}
	for _, u in ipairs(list) do
		if battle:isHostile(caster, u) then foes[#foes + 1] = u else allies[#allies + 1] = u end
	end
	local turns = self.turns or 2
	local sky, earth = L.spell(self.sky), L.spell(self.earth)
	if sky and #allies > 0 then server:applySpellEffects(battle, caster, sky, allies, 3, turns, false) end
	if earth and #foes > 0 then server:applySpellEffects(battle, caster, earth, foes, 3, turns, false) end
	L.show(server, battle, allies, self.skyAnimation, self.skySound)
	local total = 0
	for _, u in ipairs(foes) do
		if u:isAlive() then
			local amount = math.floor((self.per or 8) * caster:getCount() * (100 - L.schoolReduction(u, "earth")) / 100)
			if amount > 0 then total = total + (L.hit(server, battle, u, amount, self.animation, self.sound) or 0) end
		end
	end
	if #foes > 0 then L.log(server, battle, "H6_AREA_H6C", 4, { L.name(caster) }, { #foes, total }) end
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

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

--- Hover estimate: same formula as apply. A non-flying enemy stack takes per x number of casters earth damage (after earth and all-spell reductions);
--- allies are only hasted, returns 0. The mass version is an untargeted spell and has no hover
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	if self.mass then return zero end
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local u = first and first.unit
		if u == nil or not u:isAlive() or not battle:isHostile(caster, u) then return zero end
		local amount = math.floor((self.per or 8) * caster:getCount() * (100 - L.schoolReduction(u, "earth")) / 100)
		local d, killed = hcHit(u, amount)
		return { hpDelta = -d, unitsDelta = -killed }
	end)
	if ok and result then return result end
	return zero
end

return Script
