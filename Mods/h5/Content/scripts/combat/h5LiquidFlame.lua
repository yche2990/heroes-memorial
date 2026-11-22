local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Liquid Flame Breath (H5 Magma Dragon)
--- After an active melee attack, fire is left on the hexes of the attacked stack, lasting turns rounds (default 2);
--- stacks entering the fire take val x (Magma Dragon count) Fire damage (default 10 per creature).
--- How: places a spell obstacle with trigger spell h5LiquidFlameTrigger (Fire damage, damage = spell power recorded by the obstacle).
--- Parameters: val, turns

local TRIGGER = "heroes-memorial.h5:h5LiquidFlameTrigger"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local target = A.primary(payload, other)
	if target == nil then return end
	local spell = LIBRARY:getSpellByName(TRIGGER) or LIBRARY:getSpellByName("h5LiquidFlameTrigger")
	if spell == nil then return end
	local power = (self.val or 10) * unit:getCount()
	local hs = target:getHexes()
	for i = 1, hs:size() do
		local h = hs:at(i)
		local exists = false
		for _, o in ipairs(battle:getObstaclesOnPos(h, false) or {}) do
			local s = o:getSpell()
			if s ~= nil and s:getJsonKey() == spell:getJsonKey() then exists = true end
		end
		if not exists and h:isAvailable() then
			server:addObstacle(battle, {
				pos              = h,
				obstacleType     = ENUM.ObstacleType.spellCreated,
				spell            = spell,
				casterSpellPower = power,
				spellLevel       = 0,
				casterSide       = unit:getSide(),
				turnsRemaining   = self.turns or 2,
				hidden           = false,
				passable         = true,
				nativeVisible    = true,
				trap             = false,
				removeOnTrigger  = false,
				trigger          = TRIGGER,
				appearSound      = "",
				appearAnimation  = "h5/fx/Buildings_Campfire",
				animation        = "h5/fx/fx_campfireLoop",
				removalAnimation = "h5/fx/Characters_hits_fire_hit",
				customSize       = { h }
			})
		end
	end
end

return Script
