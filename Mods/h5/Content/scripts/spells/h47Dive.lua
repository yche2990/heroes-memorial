local Base = require("spells/spellEffect")
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Battle Dive, take-off (H4-H7 mechanic port, round 129; matches the H5 Imperial Griffin)
---
--- Griffin's active ability, cast on a hex of the battlefield: places a landing mark on that hex and the Griffin leaves the battlefield (temporarily gone,
--- not in the turn order, cannot be attacked or targeted by spells, count and health kept).
--- At the start of the next round combat/h47DiveLand makes it dive onto the marked hex, dealing damage, and puts it back on the battlefield.
---
--- Parameters (set in the spell's battleEffects):
---   mark        name of this mod's hidden mark bonus (e.g. "H47_DIVE_LOSTTALES"), stores the landing hex; value descriptions 1-3 are battle log texts
---               Round 153: value = landing hex index + 1 + (take-off hex index + 1) x 1000
---   landScript  full name of the landing script (e.g. "the-lost-tales:h47DiveLand"), added to the battlefield at take-off
---   factor      landing damage as a multiple of a normal attack, default 2
---   markAppear / markAnimation  appearing and persistent animations of the landing mark

local W = 17

local function hexIndex(hex)
	return hex:getX() + hex:getY() * W
end

local function reject(mechanics, problem)
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil then return reject(mechanics, problem) end

	local hex = dest.hex
	if not hex:isValid() or not hex:isAvailable() then return reject(mechanics, problem) end

	-- Hexes with walls or arrow towers cannot be landing hexes
	local battle = mechanics:getBattle()
	if battle:hasFortifications() and battle:hexToWallPart(hex) ~= ENUM.WallPart.invalid then
		return reject(mechanics, problem)
	end

	-- Cannot land on itself
	local caster = mechanics:getUnitCaster()
	if caster ~= nil and caster:coversPos(hex) then return reject(mechanics, problem) end

	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end

	local dest = target[1]
	if dest == nil or dest.hex == nil then return end
	local hex = dest.hex
	local spell = mechanics:getSpell()
	local source = caster:getCreature():getJsonKey()

	-- Round 344: AI simulation branch (ai-skills-design #16, #17). Leaving the field, the landing mark and the landing script are all worth 0 in the AI's estimate.
	-- So the landing strike is reported instead: if an enemy is on the landing hex, deduct one attack x factor x 0.6 (it lands next round, the enemy may move away)
	-- - 0.5 x one attack (landing uses the next round's action); 0 if no enemy is on the landing hex. Real casts never go here; this section is identical word for word in the scripts of the same name in 4 mods
	if Proxy.trial(server) then
		local v = battle:getUnitByPos(hex, true)
		if Proxy.hostile(battle, caster, v) then
			local atk = Proxy.attackEstimate(caster, v, 100, false)
			Proxy.damage(server, battle, v, atk * ((self.factor or 2) * 0.6 - 0.5))
		end
		return
	end

	-- Landing mark: visible to both sides, blocks nothing, triggers nothing
	server:addObstacle(battle, {
		pos              = hex,
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = spell,
		casterSpellPower = 0,
		spellLevel       = 0,
		casterSide       = mechanics:getCasterSide(),
		turnsRemaining   = -1,
		hidden           = false,
		passable         = true,
		nativeVisible    = true,
		trap             = false,
		removeOnTrigger  = false,
		trigger          = "",
		appearSound      = "",
		appearAnimation  = self.markAppear or "",
		animation        = self.markAnimation or "",
		removalAnimation = "",
		customSize       = { hex },
	})

	-- Record the landing hex and the take-off hex (round 153: if no free hex is found on landing, it returns to the take-off hex)
	server:addUnitBonus(battle, caster, {
		type       = self.mark,
		val        = hexIndex(hex) + 1 + (hexIndex(caster:getPosition()) + 1) * 1000,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = source,
		hidden     = true
	}, true)

	-- The landing script is added to the battlefield and triggered by the stacks on the field at the start of the next round (only one copy of the same script)
	if server:describeChanges() then -- Round 156: skipped when the AI simulates this move (such commands are not allowed in the simulation and used to flood errors)
		server:addBattleBonus(battle, {
			type       = "COMBAT_EVENT_TRIGGER",
			subtype    = self.landScript,
			val        = 0,
			duration   = "ONE_BATTLE",
			sourceType = "OTHER",
			stacking   = self.landScript,
			addInfo    = { mark = self.mark, spell = spell:getJsonKey(), factor = self.factor or 2 }
		})
	end

	server:appendLog(battle, {
		append         = { "core.bonus." .. self.mark .. ".description.1" },
		replaceStrings = { caster:getCreature():getNameTextID(caster:getCount()) }
	})

	-- Take-off: play the vanishing effect of Teleport, then leave the field
	if server:describeChanges() then -- Round 156: skipped when the AI simulates this move (such commands are not allowed in the simulation and used to flood errors)
		server:showBattleAnimation(battle, { { unit = caster } }, "h47/fx/fx_diveTakeoff", "TELPTOUT", 1.0) -- Round 184: must wait until it finishes (the stack leaves right after, and a queued cast animation must not outlast its leaving or the game hangs); round 150: a dedicated take-off animation (previously borrowed Teleport C18SPW0)
	end

	local state = caster:copy()
	state:setGhost(true)
	-- Round 153: a Griffin off the field no longer rolls good morale (a success used to give an extra turn to walk, attack and even dive again, leaving the landing mark forever)
	state:setHadMorale(true)
	-- Round 153: the position is cleared while off the field. The engine uses the position to decide whether a stack is on the battlefield: a Griffin off the field used to keep its old hex (blocking the way),
	-- and healing, dispel and other spells, the AI, Berserk and automatic shooting still targeted it. combat/h47DiveLand puts it back on landing
	state:setPosition(-1)
	server:changeUnit(battle, state)
end

return Script
