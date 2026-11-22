local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7AttackLib")
local C = require("heroes-memorial:combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Eternal Servitude (Necropolis ultimate Eternal Servitude; a permanent bonus on the hero, whose limiter only applies to Skeletal Soldiers, Skeletal Warriors,
--- and the original Skeletons and Skeleton Warriors). Original: after Skeletal Soldiers/Warriors attack (if not wiped out), 40% of the stack's dead are raised.
--- After its own attack (Yu's decision, H7 audit C2: counterattacks do not count, double attacks count once after the first hit), if the stack is still alive it raises val% (default 40) x (battle-start count - current count), with the fraction as a chance of one more.
--- Raising is permanent (like Vampire life drain); with the Ring of Oblivion (HOTA_RING_OF_OBLIVION) nothing is raised, only the top creature is healed (h5Common.reviveHeal).
--- Summons and clones do not trigger it.

local ANIM = "C01SPE0"
local SOUND = "RESURECT"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload and payload.isCounter then return end
	if payload and (payload.attackIndex or 0) > 0 then return end
	if not unit:isAlive() or unit:isGhost() or unit:isClone() or unit:copy():isSummoned() then return end
	local pct = self.val or 40
	local lost = unit:getBaseAmount() - unit:getCount()
	if pct <= 0 or lost <= 0 then return end
	local exact = lost * pct / 100
	local n = math.floor(exact)
	local frac = exact - n
	if frac > 0 and server:rngInt(1, 1000) <= math.floor(frac * 1000 + 0.5) then n = n + 1 end
	if n <= 0 then return end
	local maxHp = unit:getMaxHealth()
	local amount, level = C.reviveHeal(unit, n * maxHp + (maxHp - unit:getFirstHPleft()))
	if amount <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, ANIM, SOUND, 1.0, true)
	local _, raised = server:healUnit(battle, unit, amount, level, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	if raised and raised > 0 then
		server:appendLog(battle, {
			append = { "core.bonus.H7_SANCTUM_H7C.description.2" },
			replaceStrings = { L.name(unit) },
			replaceNumbers = { raised }
		})
	end
end

return Script
