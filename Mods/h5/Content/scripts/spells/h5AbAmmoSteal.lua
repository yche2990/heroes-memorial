local Base = require("spells/unitEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Steal Ammo (H5 Poltergeist): cast on an enemy shooter within movement range (ignoring obstacles), stealing ceil(poltergeist count / 10) + 1 shots.
--- Ammo is reduced by a negative SHOTS bonus (whole battle); unlimited (cast refunded).
--- Parameters: perCreatures (poltergeists per shot stolen, default 10), bonus (extra shots stolen, default 1), mark (bonus name for the battle log)

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) or not unit:isAlive() or unit:isTurret() then return false end
	local caster = mechanics:getUnitCaster()
	if caster == nil or not mechanics:getBattle():isHostile(caster, unit) then return false end
	if not unit:isShooter() then return false end
	local ok, speed = pcall(function() return caster:getBonusesValue({ type = "STACKS_SPEED" }) end)
	if ok and type(speed) == "number" and speed > 0 and C.unitDistance(caster, unit) > speed + 1 then return false end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	-- Round 344: AI simulation branch (ai-skills-design #41). The AI only values SHOTS when ammo is below 8: report "shots stolen / 8 rounds x
	-- shooter total health x 0.6" instead, capped as a weak ability. Real casts do not go through here
	if Proxy.trial(server) then
		local unit = target[1] and target[1].unit
		if unit == nil or not unit:isAlive() or not unit:isShooter() then return end
		local n = math.ceil(caster:getCount() / (self.perCreatures or 10)) + (self.bonus or 1)
		local left = unit:getBonusesValue({ type = "SHOTS" })
		local hp = Proxy.capWeak(unit:getAvailableHealth() * math.min(n, math.max(0, left)) / 8 * 0.6, battle, caster, unit)
		if hp >= unit:getMaxHealth() then Proxy.damage(server, battle, unit, hp) end
		return
	end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local n = math.ceil(caster:getCount() / (self.perCreatures or 10)) + (self.bonus or 1)
			server:addUnitBonus(battle, unit, {
				type       = "SHOTS",
				val        = -n,
				valueType  = ENUM.BonusValueType.additiveValue,
				duration   = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other,
				sourceID   = caster:getCreature():getJsonKey()
			}, true)
			if server:describeChanges() and self.mark then
				L.log(server, battle, self.mark, 1, { C.name(caster), C.name(unit) }, { n })
			end
		end
	end
	L.useCast(server, battle, caster, "h5AbAmmoSteal")
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
	function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
		return nil
	end
end

return Script
