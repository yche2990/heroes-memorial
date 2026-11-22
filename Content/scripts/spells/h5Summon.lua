--- H5 summoning spells (Summon Elementals, Summon Phoenix).
--- Parameters:
---   ids          list of creatures that can be summoned; with several, one is picked by battlefield, random on unrecognized battlefields
---   byTerrain    ids are Fire, Water, Earth and Air elementals in order: first special battlefields (Fiery Fields/Rocklands/Magic Clouds/Lucid Pools),
---                then the terrain marker (global hidden bonus NONE limited by terrain in the mod settings, value 1 Fire 2 Water 3 Earth 4 Air)
---   fx           summon animations matching ids, deferred until the new stack appears
---   base, perPower  count (or total health with byHealth) = trunc(base + perPower*SP)
---   byHealth     true: count converted from total health (Summon Phoenix: 30x(10+SP)x ratio)
---   permanent    whether it stays after battle
---   exclusive    as core summon
local Base = require("spells/summon")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:firstCreature()
	return LIBRARY:getCreatureByName(self.ids[1])
end

function Script:rawAmount(mechanics)
	return math.floor(Lib.value(self.base, self.perPower, Lib.level(mechanics), Lib.power(mechanics)))
end

function Script:amountFor(mechanics, creature)
	local raw = mechanics:applySpecificSpellBonus(self:rawAmount(mechanics))
	if self.byHealth then
		return math.floor(raw / creature:getMaxHealth())
	end
	return raw
end

function Script:summonedCreatureAmount(mechanics)
	return self:amountFor(mechanics, self:firstCreature())
end

function Script:applicableGeneral(mechanics, problem)
	self.id = self.ids[1]
	return Base.applicableGeneral(self, mechanics, problem)
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	self.id = self.ids[1]
	return Base.transformTarget(self, mechanics, aimPoint, spellTarget)
end

-- Elements of special battlefields (as the magic school bonuses of H3)
local OVERLAY = { fiery_fields = 1, lucid_pools = 2, rocklands = 3, magic_clouds = 4 }

--- Recognizes the element by battlefield, returning the index in ids; nil if not recognized
function Script:terrainIndex(battle)
	local units = battle:getUnitsIf(function(u) return true end)
	for _, u in ipairs(units) do
		local ov = u:getBonuses({ sourceType = ENUM.BonusSource.terrainOverlay })
		for i = 1, ov:size() do
			local id = ov:getBonus(i):getSourceID() or ""
			id = id:gsub("^.*:", "")
			if OVERLAY[id] then return OVERLAY[id] end
		end
	end
	for _, u in ipairs(units) do
		local mk = u:getBonuses({ type = "NONE", sourceType = ENUM.BonusSource.global })
		for i = 1, mk:size() do
			local v = mk:getBonus(i):getVal()
			if v >= 1 and v <= 4 then return v end
		end
	end
	return nil
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local idx = 1
	if #self.ids > 1 then
		idx = (self.byTerrain and self:terrainIndex(battle)) or server:rngInt(1, #self.ids)
	end
	local pick = self.ids[idx]
	local creature = LIBRARY:getCreatureByName(pick)
	if not creature then return end
	for _, dest in ipairs(target) do
		if dest.unit == nil and dest.hex ~= nil then
			local n = self:amountFor(mechanics, creature)
			if n > 0 then
				if self.fx and self.fx[idx] and server:describeChanges() then   -- No animations during the AI simulation (checklist section 10)
					server:showBattleAnimation(battle, { { hex = dest.hex } }, self.fx[idx], "", 1.0, true)
				end
				server:addUnit(battle, {
					count = n,
					type = creature,
					side = mechanics:getCasterSide(),
					position = dest.hex,
					summoned = not self.permanent
				})
			end
		end
	end
end

return Script
