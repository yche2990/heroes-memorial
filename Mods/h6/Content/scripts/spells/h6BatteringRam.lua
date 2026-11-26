local Base = require("spells/spellEffect")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local WALLS  = {
	ENUM.WallPart.bottomWall,
	ENUM.WallPart.belowGate,
    ENUM.WallPart.overGate,
	ENUM.WallPart.upperWall
}
local BOTTOM_TOWER = ENUM.WallPart.bottomTower
local UPPER_TOWER = ENUM.WallPart.upperTower
local KEEP = ENUM.WallPart.keep
local GATE = ENUM.WallPart.gate

function Script:hasNoPotentialTargets(battle)
	for _, p in ipairs(WALLS) do
		if battle:isWallPartAttackable(p) then
			return false
		end
	end
	if self.canAttackGate and battle:isWallPartAttackable(GATE) then
		return false
	end
	if self.canAttackTowers then
		if battle:isWallPartAttackable(UPPER_TOWER) or battle:isWallPartAttackable(BOTTOM_TOWER) then
			return false
		end
	end
	if self.canAttackKeep and battle:isWallPartAttackable(KEEP) then
		return false
	end
	return true
end

function Script:randomDamage(server, sumOfVal)
	local val = math.max(0, sumOfVal)
    local baseDmg = math.floor(val / 100)
    local extraChance = val % 100
    local r = server:rngInt(0, 99)

    if r < extraChance then
        return baseDmg + 1
    end

    return baseDmg
end

function Script:allowedToAttackWallPart(wallPart)
    for _, p in ipairs(WALLS) do
        if wallPart == p then
            return true
        end
    end

    if self.canAttackGate and wallPart == GATE then
        return true
    end

	if self.canAttackTowers then
		if wallPart == BOTTOM_TOWER or wallPart == UPPER_TOWER then
			return true
		end
	end

    return self.canAttackKeep and wallPart == KEEP
end

function Script:canCasterAttackWallPart(battle, attacker, wallPart)
	if not self:allowedToAttackWallPart(wallPart) then return false end
	local casterHex = attacker:getPosition()
	local hex = battle:wallPartToBattleHex(wallPart)

	if wallPart == GATE then
		return casterHex == hex:copyToWest():copyToWest()
	end

	if wallPart == BOTTOM_TOWER then
		hex = hex:copyToWest()
	end

	if wallPart == KEEP then
		hex = hex:copyToSouthWest():copyToSouthWest():copyToSouthWest():copyToSouthEast():copyToSouthEast()
	end

	local hexes = {
		hex:copyToWest(),
		hex:copyToNorthWest(),
		hex:copyToSouthWest()
	}
	for _, targetHex in ipairs(hexes) do
		if casterHex == targetHex then
			return true
		end
	end

	return false
end

function Script:applicableTarget(mechanics, problem, target)
	local battle = mechanics:getBattle()
	local hex = target[1].hex
	local wallPart = battle:hexToWallPart(hex)
	local caster = mechanics:getUnitCaster()

	if 	not caster
		or wallPart < 0
		or not battle:isWallPartAttackable(wallPart)
		or not self:canCasterAttackWallPart(battle, caster, wallPart)
	then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end

	return true
end

function Script:applicableGeneral(mechanics, problem)
	local battle = mechanics:getBattle()

	if not battle:hasFortifications()
	   or mechanics:getCasterSide() ~= ENUM.BattleSide.attacker
	   or self:hasNoPotentialTargets(battle)
	then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end

	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local attacker  = mechanics:getUnitCaster()
	local part = battle:hexToWallPart(target[1].hex)
	local attackStrength = attacker:getBonusesValue({ type = "BATTERING_RAM" })
	local damage = self:randomDamage(server, attackStrength)
	server:catapultAttack(battle, nil, part, damage)
	self:describe(server, battle, attacker, damage)
end

function Script:describe(server, battle, attacker, damage)
	local count = attacker:getCount()
	server:appendLog(battle, {
		append         = { count == 1 and "spell.batteringram.batteringRam.batteringRam.singular" or "spell.batteringram.batteringRam.batteringRam.plural" },
		replaceStrings = { attacker:getCreature():getNameTextID(count) },
		replaceNumbers = { damage }
	})
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Siege Ram: the target is a wall section, with the catapult aiming cursor (the script is in the batteringRam mod and not in the export)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "combatShootCatapult" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
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

return Script