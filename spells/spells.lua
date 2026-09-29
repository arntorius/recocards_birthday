-- mods/recocards_birthday/spells/spells.lua
-- Loaded by init.lua (dofile_once) AND by the temple_altar_left.lua override.
-- This is the single place to edit the birthday spells.

-- Pool of spells. One is picked at random for each slot (no repeats),
-- and it's different per world seed.
BIRTHDAY_SPELL_POOL = { 
    "RHM_CONFETTI",
    "RHM_BALD_SHOT",
    "RHM_TOOBALD",
    "RHM_HAPPY_PARTY",
    "RHM_CELEBRATIUM_PIXEL",
    "RHM_FRIEND",
    "RHM_SWEAT",
    "RHM_GOD_GAMER",
    "RHM_CAKE_THROWER",
    "RHM_DUNKBOT"
}

-- Slots, in altar_left.png pixel coordinates. Both sit on the two blocks in the small room.
-- Left slot was x=98 -> moved 3px left = 95. Right slot was x=138 -> moved 3px right = 141.
-- y is now EXACT: the spell stays precisely where you put it (no falling).
-- Bigger y = lower on screen, smaller y = higher. 1 unit = 1 pixel.
-- The blocks' top surface is at y=123; ~115 puts a spell resting on top of it.
BIRTHDAY_SPELL_SLOTS = {
    { x = 95,  y = 115 },
    { x = 141, y = 115 },
}

-- If the temple's init() runs more than once for the same Holy Mountain, only spawn once.
local DUPLICATE_RADIUS = 400

local function already_spawned_near(scene_x, scene_y)
    local ok, list = pcall(GlobalsGetValue, "reco_spell_spawns", "")
    if not ok or list == nil or list == "" then return false end
    for px, py in string.gmatch(list, "(-?%d+%.?%d*),(-?%d+%.?%d*);") do
        local dx, dy = tonumber(px) - scene_x, tonumber(py) - scene_y
        if dx * dx + dy * dy < DUPLICATE_RADIUS * DUPLICATE_RADIUS then return true end
    end
    return false
end

local function remember_spawn(scene_x, scene_y)
    pcall(function()
        local list = GlobalsGetValue("reco_spell_spawns", "") or ""
        GlobalsSetValue("reco_spell_spawns", list .. scene_x .. "," .. scene_y .. ";")
    end)
end

-- Spells are physics bodies. They used to fall before the temple's pixel scene finished
-- loading, so they landed at unpredictable heights inside the altars. Disabling the body
-- (and velocity) pins the spell at the exact spawn position. It can still be picked up.
local function freeze_in_place(entity)
    pcall(function()
        for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "PhysicsBodyComponent") or {}) do
            ComponentSetValue2(c, "is_enabled", false)
        end
        for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "VelocityComponent") or {}) do
            ComponentSetValue2(c, "updates_velocity", false)
        end
        for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "SimplePhysicsComponent") or {}) do
            EntityRemoveComponent(entity, c)
        end
    end)
end

-- Called from temple_altar_left.lua's init() with the pixel scene's top-left corner.
function SpawnBirthdaySpells(scene_x, scene_y)

    if already_spawned_near(scene_x, scene_y) then
        return
    end
    remember_spawn(scene_x, scene_y)

    -- shuffle a copy of the pool (deterministic per world seed + location)
    SetRandomSeed(scene_x, scene_y)
    local pool = {}
    for i, id in ipairs(BIRTHDAY_SPELL_POOL) do pool[i] = id end
    for i = #pool, 2, -1 do
        local j = Random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    for i, slot in ipairs(BIRTHDAY_SPELL_SLOTS) do
        local id = pool[i] or pool[1]
        local e = CreateItemActionEntity(id, scene_x + slot.x, scene_y + slot.y)
        if e ~= nil and e ~= 0 then freeze_in_place(e) end
    end
end