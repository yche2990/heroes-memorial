local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Memorial Shrine: Urgash's Call (approximation of the Inferno ultimate Urgash's Call):
--- at battle start every Inferno stack (bonus limited by FACTION_LIMITER) immediately summons a stack of the same creature through the Gating,
--- count val% of that stack (default 40%, fractions give 1 more by chance). The reinforcements are summoned, vanish after battle, and act normally this round.
--- Original: Inferno creatures' "Gating" (hero skill, reinforcements 30/35/40/45% of the stack) waits one round first; the ultimate makes them appear at once.
--- Summoned creatures, clones, turrets, commanders and war machines do not summon; the hero's faction does not matter (the bonus is only on the hero with the ultimate).

local LOG = "H5_URGASH_LOG_H5C"

function Script:onBattleStart(server, battle, unit, other, payload)
	-- Summoned creatures detected with copy():isSummoned() (checklist section 10); commanders and war machines do not summon (audit C-12)
	if not unit:isAlive() or unit:isClone() or unit:copy():isSummoned() or unit:isTurret() then return end
	if unit:isCommander() or unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
	local pct = self.val or 40
	if pct <= 0 then return end
	local exact = unit:getCount() * pct / 100
	local count = math.floor(exact)
	local frac = exact - count
	if frac > 0 and server:rngInt(1, 1000) <= math.floor(frac * 1000 + 0.5) then
		count = count + 1
	end
	if count <= 0 then return end
	local creature = unit:getCreature()
	local hex = battle:getAvailableHex(creature, unit:getSide(), unit:getPosition())
	if hex == nil or not hex:isValid() then return end
	local added = server:addUnit(battle, {
		count    = count,
		type     = creature,
		side     = unit:getSide(),
		position = hex,
		summoned = true
	})
	if added == nil then return end
	server:showBattleAnimation(battle, { { hex = hex } }, "h5/fx/Characters_SummonBalor", "SUMNELM", 0.6, true)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus." .. LOG .. ".description.1" },
		replaceStrings = { creature:getNameTextID(count) },
		replaceNumbers = { count }
	})
end

return Script
