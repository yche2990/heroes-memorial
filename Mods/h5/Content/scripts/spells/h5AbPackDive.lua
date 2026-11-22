local Base = require("spells/spellEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Pack Dive (H5 Battle Griffin): once per battle. Takes off from a chosen battlefield hex and leaves the field (cannot be attacked meanwhile, not in the turn order),
--- and at the start of the next round dives down via combat/h5AbPackDiveLand, attacking all enemies in that hex's row and the row below (H5's "two horizontal rows"),
--- for pct% of normal attack damage (original 75%), no retaliation; then it returns to the takeoff spot (nearest free hex if occupied).
--- Parameters: landScript (full name of the landing script), pct, mark (hidden mark type: value = landing hex + 1 + (takeoff hex + 1) x 1000), markAnimation

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	local battle = mechanics:getBattle()
	if battle:hasFortifications() and battle:hexToWallPart(dest.hex) ~= ENUM.WallPart.invalid then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local dest = spellTarget[1]
	if dest and dest.hex and dest.hex:isValid() then
		local y = dest.hex:getY()
		for _, h in pairs(C.hexTable(mechanics:getBattle())) do
			if h:isAvailable() and (h:getY() == y or h:getY() == y + 1) then hexes:insert(h) end
		end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local hex = target[1] and target[1].hex
	if hex == nil then return end
	local spell = mechanics:getSpell()
	local source = caster:getCreature():getJsonKey()

	-- Round 344: AI simulation branch (ai-skills-design #18). Leaving the field is worth 0 in the AI's estimate. The landing sweep is reported instead:
	-- each enemy in the landing row and the row below loses one attack x pct% x 0.6, then 0.5 x one attack is subtracted from the one hit hardest (landing uses up the next round).
	-- Real casts do not go through here
	if Proxy.trial(server) then
		local y = hex:getY()
		local list, best, bestHp, total = {}, nil, 0, 0
		for _, u in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) end)) do
			local hs, inRows = u:getHexes(), false
			for i = 1, hs:size() do
				local hy = hs:at(i):getY()
				if hy == y or hy == y + 1 then inRows = true end
			end
			if inRows then
				local hp = Proxy.attackEstimate(caster, u, self.pct or 75, false) * 0.6
				list[#list + 1] = { u = u, hp = hp }
				total = total + hp
				if hp > bestHp then best, bestHp = u, hp end
			end
		end
		if best == nil then return end
		local lost = 0.5 * Proxy.attackEstimate(caster, Proxy.nearestHostile(battle, caster) or best, 100, false)
		if total <= lost then return end
		for _, e in ipairs(list) do
			Proxy.damage(server, battle, e.u, e.u == best and (e.hp - lost) or e.hp)
		end
		return
	end

	server:addUnitBonus(battle, caster, {
		type       = self.mark,
		val        = C.hexIndex(hex) + 1 + (C.hexIndex(caster:getPosition()) + 1) * 1000,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = source,
		hidden     = true
	}, true)

	if server:describeChanges() then
		server:addBattleBonus(battle, {
			type       = "COMBAT_EVENT_TRIGGER",
			subtype    = self.landScript,
			val        = 0,
			duration   = "ONE_BATTLE",
			sourceType = "OTHER",
			stacking   = self.landScript,
			addInfo    = { mark = self.mark, pct = self.pct or 75 }
		})
		server:appendLog(battle, {
			append         = { "core.bonus." .. self.mark .. ".description.1" },
			replaceStrings = { caster:getCreature():getNameTextID(caster:getCount()) }
		})
		-- Then the stack leaves the field: this animation is not deferred (rule of round 184)
		server:showBattleAnimation(battle, { { unit = caster } }, "h5/fx/fx_diveTakeoff", "TELPTOUT", 1.0)
	end

	local state = caster:copy()
	state:setGhost(true)
	state:setHadMorale(true)
	state:setPosition(-1)
	server:changeUnit(battle, state)
	L.useCast(server, battle, caster, "h5AbPackDive", 1)
end

return Script
