local Base = require("spells/spellEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Berserker Rage (H5 Berserker): cast on itself, Defense drops to 0 and all the Defense lost is added to Attack;
--- after that it automatically attacks the nearest stack (an ally if there is no enemy), and targets cannot retaliate. The effect lasts until the battle ends;
--- casting again ends the rage (in H5 it can be switched on and off at any time). Casting uses nothing beyond the action (unlimited).
--- Parameters: show (display bonus type), mark (bonus name for the battle log, value description 1 = enters rage, 2 = ends rage)

local STACK = "h5BerserkerRage"

local function own(unit)
	return unit:getBonuses({ sourceType = ENUM.BonusSource.creatureAbility }):filter(function(b)
		return b:getStacking() == STACK
	end)
end

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local old = own(caster)
	-- Round 344: AI simulation branch (ai-skills-design #27). The effect already uses native bonuses the AI knows and is valued as is; only "automatically attack the nearest stack"
	-- is penalized in the AI's model by how crowded allies are on the whole field (ignoring position); here position counts instead: not applied when no ally is within 2 hexes of the caster (no ally can be hit).
	-- Ending the rage as before. Real casts do not go through here
	if old:size() == 0 and Proxy.trial(server) then
		local d = caster:getDefense(false)
		local function add(desc) desc.stacking = STACK; desc.duration = ENUM.BonusDuration.oneBattle; Proxy.buff(server, battle, caster, desc) end
		add({ type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -d })
		add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = d })
		add({ type = "BLOCKS_RETALIATION", val = 0 })
		local friends = battle:getUnitsIf(function(x)
			return x:isAlive() and not x:isGhost() and x:unitID() ~= caster:unitID() and not battle:isHostile(caster, x)
				and Proxy.unitsDistance(x, caster) <= 2
		end)
		if #friends > 0 then add({ type = "ATTACKS_NEAREST_CREATURE", val = 0 }) end
		return
	end
	if old:size() > 0 then
		-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
		Proxy.removeExact(server, battle, caster, old)
		if server:describeChanges() then L.log(server, battle, self.mark, 2, { C.name(caster) }) end
	else
		local d = caster:getDefense(false)
		local function add(desc)
			desc.stacking = STACK
			desc.duration = ENUM.BonusDuration.oneBattle
			L.addBonus(server, battle, caster, desc, true)
		end
		add({ type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -d })
		add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = d })
		add({ type = "ATTACKS_NEAREST_CREATURE", val = 0, hidden = true })
		add({ type = "BLOCKS_RETALIATION", val = 0, hidden = true })
		add({ type = self.show, val = d })
		if server:describeChanges() then
			-- The original Berserker Rage visual is the creature's own animation; the borrowed H3 animation is no longer added (audit B III-1)
			server:refreshBattleUnits(battle)
			L.log(server, battle, self.mark, 1, { C.name(caster) }, { d })
		end
	end
	L.useCast(server, battle, caster, "h5AbBerserkerRage")
end

return Script
