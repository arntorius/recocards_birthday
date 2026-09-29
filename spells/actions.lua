-- mods/recocards_birthday/spells/actions.lua
--
-- ONE file, three jobs (it works out which one from the context it's loaded in):
--   1. gun mode    : appended to gun_actions.lua by init.lua's ModLuaFileAppend -> registers the spells
--   2. init mode   : init.lua runs it once with RECO_SPELL_INIT = true -> writes the projectile XML
--                    files *virtually* (nothing is created on disk, you never make an XML file)
--   3. script mode : the generated projectiles point their LuaComponent back at this file, which runs
--                    the per-frame logic (particles, knockback, deleting things, etc.)
--
-- Needs these lines in init.lua (near the existing ModLuaFileAppend for this file):
--     RECO_SPELL_INIT = true
--     dofile("mods/recocards_birthday/spells/actions.lua")
--     RECO_SPELL_INIT = nil

local DIR  = "mods/recocards_birthday/spells/"
local ICON = DIR .. "icons/"        -- 16x16 spell card icons
local SPR  = DIR .. "spells/"       -- projectile sprites
local GEN  = DIR .. "generated/"    -- virtual XML (does not exist on disk)
local SELF = DIR .. "actions.lua"

---------------------------------------------------------------- config (tune me)
local CFG = {
    -- entity file used for "Happy Party".
    hamis_entity         = "data/entities/animals/longleg.xml",
    -- material name from your celebratium materials.xml
    celebratium_material = "celebratium_confetti",
    -- Sweat converts water into the first of these that exists in your game
    grease_candidates    = { "grease", "fat", "oil" },
    -- pixel size of each projectile sprite (used to centre it). Change if your PNGs aren't 16x16.
    sprite_size          = { bald_shot = { 360, 360 }, cake = { 80, 80 }, dunkbot = { 240, 240 } },
    -- This shrinks the image in-game while keeping the HD detail (1.0 = normal, 0.5 = half size)
    sprite_scale         = { bald_shot = 0.15, cake = 0.4, dunkbot = 0.15 },
    confetti_count       = 6,
    confetti_dig_radius  = 2,      -- px of terrain removed where a spark dies
    
    -- Made significantly smaller than the main projectile (0.15)
    bald_particle_scale  = 0.08,
    
    cake_knockback       = 1020,    -- px/s
    cake_hit_radius      = 9,
    dunkbot_radius       = 48,
    dunkbot_lifetime = 240,
    dunkbot_speed = 220,
    friend_range         = 450,
    sweat_radius         = 14,
    party_hamis          = 20,
    party_hamis_hp       = 1000,   -- shown hp; converted internally (x25)
}

local DEFAULT_SOUND_BANK  = "data/audio/Desktop/projectiles.bank"
local DEFAULT_SOUND_ROOT  = "player_projectiles/bullet_light"

---------------------------------------------------------------- shared helpers
local function b(v) if v then return 1 else return 0 end end

local function get_born(me)
    local v = EntityGetFirstComponent(me, "VariableStorageComponent", "reco_born")
    if v == nil then
        v = EntityAddComponent2(me, "VariableStorageComponent", { name = "reco_born", value_int = GameGetFrameNum() })
        ComponentAddTag(v, "reco_born")
    end
    return ComponentGetValue2(v, "value_int")
end

-- Extra entities (tooBald / Sweat) may be merged into the projectile or attached as a child.
local function get_proj(me)
    if EntityGetFirstComponent(me, "ProjectileComponent") ~= nil then return me end
    local p = EntityGetParent(me)
    if p ~= nil and p ~= 0 then return p end
    return me
end

local function seed(a, b2) SetRandomSeed(GameGetFrameNum() + (a or 0), (b2 or 0) + 7) end

local function usable_material(name)
    local ok, t = pcall(CellFactory_GetType, name)
    return ok and t ~= nil and t > 0
end

local SPARK_MATS
local function spark_mats()
    if SPARK_MATS == nil then
        SPARK_MATS = {}
        for _, m in ipairs({ "spark", "spark_red", "spark_green", "spark_blue", "spark_white" }) do
            if usable_material(m) then SPARK_MATS[#SPARK_MATS + 1] = m end
        end
    end
    return SPARK_MATS
end

local function confetti_puff(x, y, n)
    local mats = spark_mats()
    if #mats == 0 then return end
    for _ = 1, n do
        local m = mats[Random(1, #mats)]
        GameCreateParticle(m, x, y, 1, Random(-30, 30), Random(-30, 30), true)
    end
end

local function play_default_sound(x, y)
    pcall(GamePlaySound, DEFAULT_SOUND_BANK, DEFAULT_SOUND_ROOT .. "/create", x, y)
end

local function shooter_info()
    local wand   = GetUpdatedEntityID()
    local player = EntityGetRootEntity(wand)
    local x, y   = EntityGetTransform(player)
    local ax, ay = 1, 0
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    if controls ~= nil then
        local vx, vy = ComponentGetValue2(controls, "mAimingVectorNormalized")
        if vx ~= nil then ax, ay = vx, vy end
    end
    return player, x, y, ax, ay
end

---------------------------------------------------------------- script mode (per-entity logic)
local function emit_bald_particle(x, y)
    -- 1. Create the ROOT entity (Handles movement and bouncing)
    local p = EntityCreateNew()
    EntitySetTransform(p, x, y)
    local life = Random(60, 120) 
    
    EntityAddComponent2(p, "VelocityComponent", { 
        gravity_y = Random(50, 150),
        air_friction = 1.2
    })
    
    EntityAddComponent2(p, "ProjectileComponent", {
        lifetime = life, damage = 0, speed_min = 80, speed_max = 300,
        collide_with_world = true, collide_with_entities = false, on_collision_die = false,
        velocity_sets_rotation = true, ground_collision_fx = false,
        bounces_left = 5, bounce_energy = 0.6
    })
    
    EntityAddComponent2(p, "LifetimeComponent", { lifetime = life })
    
    -- 2. Create the CHILD entity (Holds the visual sprite safely)
    local visual = EntityCreateNew()
    
    -- THE FIX: We MUST move the child to the correct coordinates BEFORE attaching it
    EntitySetTransform(visual, x, y)
    EntityAddChild(p, visual)
    
    local size = CFG.sprite_size.bald_shot
    EntityAddComponent2(visual, "SpriteComponent", {
        image_file = SPR .. "bald_shot.png",
        offset_x = size[1] / 2, offset_y = size[2] / 2,
        has_special_scale = true,
        special_scale_x = CFG.bald_particle_scale, special_scale_y = CFG.bald_particle_scale,
        z_index = -2, 
    })
    
    -- Attach shrinking script to the visual child
    local l = EntityAddComponent2(visual, "LuaComponent", { script_source_file = SELF, execute_every_n_frame = 1 })
    ComponentAddTag(l, "reco_script")
    ComponentAddTag(l, "reco_shrink")
    
    -- 3. Shoot it in a completely random direction
    local a = Random(0, 628) / 100
    local speed = Random(100, 350)
    GameShootProjectile(0, x, y, x + math.cos(a) * speed, y + math.sin(a) * speed, p, false)
end

-- One cake projectile using Bald Shot's safe root + attached visual pattern.
local function emit_cake_projectile(x, y, tx, ty)
    local p = EntityCreateNew()
    EntitySetTransform(p, x, y)
    EntityAddComponent2(p, "VelocityComponent", { gravity_y = 0, air_friction = 0 })
    EntityAddComponent2(p, "ProjectileComponent", {
        lifetime = 240, damage = 0, speed_min = 380, speed_max = 380,
        collide_with_world = true, collide_with_entities = false,
        on_collision_die = false, velocity_sets_rotation = true,
        ground_collision_fx = false, bounces_left = 5, bounce_energy = 0.95,
    })
    EntityAddComponent2(p, "LifetimeComponent", { lifetime = 240 })

    local visual = EntityCreateNew()
    EntitySetTransform(visual, x, y)
    EntityAddChild(p, visual)
    local size = CFG.sprite_size.cake
    EntityAddComponent2(visual, "SpriteComponent", {
        image_file = SPR .. "cake.png", offset_x = size[1] / 2, offset_y = size[2] / 2,
        has_special_scale = true, special_scale_x = CFG.sprite_scale.cake,
        special_scale_y = CFG.sprite_scale.cake, z_index = -2,
    })
    local visual_lua = EntityAddComponent2(visual, "LuaComponent", {
        script_source_file = SELF, execute_every_n_frame = 1,
    })
    ComponentAddTag(visual_lua, "reco_script")
    ComponentAddTag(visual_lua, "reco_cake_visual")

    local root_lua = EntityAddComponent2(p, "LuaComponent", {
        script_source_file = SELF, execute_every_n_frame = 1,
    })
    ComponentAddTag(root_lua, "reco_script")
    ComponentAddTag(root_lua, "reco_cake")
    GameShootProjectile(0, x, y, tx, ty, p, false)
end

local function emit_dunkbot_projectile(x, y, tx, ty)
    local p = EntityCreateNew()
    EntitySetTransform(p, x, y)

    EntityAddComponent2(p, "VelocityComponent", {
        gravity_y = 300,
        air_friction = 0,
    })

    EntityAddComponent2(p, "ProjectileComponent", {
        lifetime = CFG.dunkbot_lifetime,

        -- Noita damage is normally expressed as HP / 25.
        -- Negative damage heals: -25 / 25 = heal 25 HP.
        damage = -125 / 25,

        speed_min = CFG.dunkbot_speed,
        speed_max = CFG.dunkbot_speed,

        collide_with_world = true,
        collide_with_entities = true,
        on_collision_die = true,

        -- Prevents it from affecting the player, including its caster.
        never_hit_player = true,
        friendly_fire = false,

        velocity_sets_rotation = true,
        ground_collision_fx = false,
        bounces_left = 3,
        bounce_energy = 0.5,
    })

    EntityAddComponent2(p, "LifetimeComponent", {
        lifetime = CFG.dunkbot_lifetime,
    })

    local visual = EntityCreateNew()
    EntitySetTransform(visual, x, y)
    EntityAddChild(p, visual)

    local size = CFG.sprite_size.dunkbot
    EntityAddComponent2(visual, "SpriteComponent", {
        image_file = SPR .. "dunkbot.png",
        offset_x = size[1] / 2,
        offset_y = size[2] / 2,
        has_special_scale = true,
        special_scale_x = CFG.sprite_scale.dunkbot,
        special_scale_y = CFG.sprite_scale.dunkbot,
        z_index = -2,
    })

    local visual_lua = EntityAddComponent2(visual, "LuaComponent", {
        script_source_file = SELF,
        execute_every_n_frame = 1,
    })
    ComponentAddTag(visual_lua, "reco_script")
    ComponentAddTag(visual_lua, "reco_dunkbot_visual")

    GameShootProjectile(0, x, y, tx, ty, p, false)
end

local function knockback(target, nx, ny)
    local power = CFG.cake_knockback
    local cd = EntityGetFirstComponent(target, "CharacterDataComponent")
    if cd ~= nil then
        ComponentSetValue2(cd, "mVelocity", nx * power, ny * power - 360)
    else
        local vc = EntityGetFirstComponent(target, "VelocityComponent")
        if vc ~= nil then ComponentSetValue2(vc, "mVelocity", nx * power, ny * power) end
    end
end

local function spawn_random_potion(x, y)
    local list = {}
    local function add(t) for _, m in ipairs(t or {}) do list[#list + 1] = m end end
    add(CellFactory_GetAllLiquids(false))
    add(CellFactory_GetAllSands(false))
    add(CellFactory_GetAllGases(false))
    add(CellFactory_GetAllFires(false))
    add(CellFactory_GetAllSolids(false))
    if #list == 0 then return end
    local potion = EntityLoad("data/entities/items/pickup/potion_empty.xml", x, y)
    if potion ~= nil and potion ~= 0 then
        AddMaterialInventoryMaterial(potion, list[Random(1, #list)], 1000)
    end
end

local TICK = {}

TICK.confetti = function(me)
    local x, y = EntityGetTransform(me)
    local born = get_born(me)
    local age  = GameGetFrameNum() - born
    seed(me, 1)
    if age % 2 == 0 then confetti_puff(x, y, 1) end
    if age >= 40 + (born + me) % 35 then
        local e = EntityCreateNew()
        EntitySetTransform(e, x, y)
        EntityAddComponent2(e, "CellEaterComponent", {
            radius = CFG.confetti_dig_radius, eat_probability = 100, eat_dynamic_physics_bodies = false,
        })
        EntityAddComponent2(e, "LifetimeComponent", { lifetime = 3 })
        confetti_puff(x, y, 6)
        EntityKill(me)
    end
end

-- Shrinks particles gracefully as they die
TICK.shrink = function(me)
    local spr = EntityGetFirstComponent(me, "SpriteComponent")
    if spr ~= nil then
        local sx = ComponentGetValue2(spr, "special_scale_x") or CFG.bald_particle_scale
        local new_s = sx * 0.98 -- Gentler shrink rate
        ComponentSetValue2(spr, "special_scale_x", new_s)
        ComponentSetValue2(spr, "special_scale_y", new_s)
    end
end

TICK.bald = function(me)
    local x, y = EntityGetTransform(get_proj(me))
    seed(me, 2)
    emit_bald_particle(x, y)
end
TICK.toobald = TICK.bald

TICK.celebratium = function(me)
    local x, y = EntityGetTransform(me)
    local vx, vy = GameGetVelocityCompVelocity(me)
    GameCreateParticle(CFG.celebratium_material, x, y, 1, vx or 0, vy or 0, false, false, false)
    EntityKill(me)
end

TICK.cake_visual = function(me)
    local parent = EntityGetParent(me)

    if parent == nil or parent == 0 or not EntityGetIsAlive(parent) then
        EntityKill(me)
        return
    end

    local x, y = EntityGetTransform(parent)
    EntitySetTransform(me, x, y)
end

TICK.cake = function(me)
    local x, y = EntityGetTransform(me)
    local pc = EntityGetFirstComponent(me, "ProjectileComponent")
    local shooter = 0
    if pc ~= nil then shooter = ComponentGetValue2(pc, "mWhoShot") end
    local age = GameGetFrameNum() - get_born(me)
    local vx, vy = GameGetVelocityCompVelocity(me)
    vx, vy = vx or 1, vy or 0
    local sp = math.sqrt(vx * vx + vy * vy)
    if sp < 1 then sp = 1 end
    local nx, ny = vx / sp, vy / sp
    for _, t in ipairs(EntityGetInRadiusWithTag(x, y, CFG.cake_hit_radius, "hittable") or {}) do
        if t ~= me and not (t == shooter and age < 15) then
            if EntityGetFirstComponent(t, "DamageModelComponent") ~= nil then
                EntityInflictDamage(t, 1 / 25, "DAMAGE_PROJECTILE", "Cake", "NORMAL", nx * 300, ny * 300, shooter)
                knockback(t, nx, ny)
                EntityKill(me)
                return
            end
        end
    end
end
TICK.dunkbot_visual = function(me)
    local parent = EntityGetParent(me)

    if parent == nil or parent == 0 or not EntityGetIsAlive(parent) then
        EntityKill(me)
        return
    end

    local x, y = EntityGetTransform(parent)
    EntitySetTransform(me, x, y)
end
TICK.dunkbot = function(me)
    -- No area sweep. ProjectileComponent handles the entity collision and the
    -- 1-point hit configured in emit_dunkbot_projectile().
end

TICK.sweat = function(me)
    local x, y = EntityGetTransform(get_proj(me))
    local grease

    for _, name in ipairs(CFG.grease_candidates) do
        if usable_material(name) then
            grease = name
            break
        end
    end

    if grease == nil then
        return
    end

    local r = CFG.sweat_radius
    local x1 = math.floor(x - r)
    local y1 = math.floor(y - r)
    local w = r * 2
    local h = r * 2

    -- Convert every registered liquid material, not just water.
    for _, liquid in ipairs(CellFactory_GetAllLiquids(false) or {}) do
        if liquid ~= grease and usable_material(liquid) then
            ConvertMaterialOnAreaInstantly(
                x1,
                y1,
                w,
                h,
                CellFactory_GetType(liquid),
                CellFactory_GetType(grease),
                false,
                false
            )
        end
    end
end

TICK.godgamer = function(me)
    local v = EntityGetFirstComponent(me, "VariableStorageComponent", "reco_gg")
    if v == nil then EntityKill(me) return end
    local sx, sy, result, start, spawned = ComponentGetValue2(v, "value_string"):match("^(%-?[%d%.]+)|(%-?[%d%.]+)|(%a+)|(%d+)|(%d+)$")
    if sx == nil then EntityKill(me) return end
    local x, y, start, spawned = tonumber(sx), tonumber(sy), tonumber(start), tonumber(spawned)
    local total = (result == "win") and 5 or 10
    local due = start + 42 + 6 * spawned
    if GameGetFrameNum() >= due then
        seed(spawned, x)
        if result == "win" then
            spawn_random_potion(x + Random(-12, 12), y - 30)
        else
            EntityLoad("data/entities/projectiles/bomb.xml", x + Random(-12, 12), y - 70)
        end
        spawned = spawned + 1
        ComponentSetValue2(v, "value_string", string.format("%s|%s|%s|%d|%d", sx, sy, result, start, spawned))
        if spawned >= total then EntityKill(me) end
    end
end

local function run_script(comp)
    local me = GetUpdatedEntityID()
    for kind, fn in pairs(TICK) do
        if ComponentHasTag(comp, "reco_" .. kind) then fn(me) return end
    end
end

---------------------------------------------------------------- init mode (virtual XML)
local function write_xml(name, xml) ModTextFileSetContent(GEN .. name .. ".xml", xml) end

local function lua_comp(kind, every)
    return string.format('<LuaComponent _tags="reco_script,reco_%s" script_source_file="%s" execute_every_n_frame="%d" />',
        kind, SELF, every or 1)
end

local function projectile_xml(o)
    local t = { string.format('<Entity name="%s" tags="projectile_player">', o.name) }
    t[#t + 1] = string.format('<VelocityComponent gravity_y="%s" air_friction="%s" mass="0.05" />', o.gravity or 0, o.friction or 0)
    t[#t + 1] = string.format(
        '<ProjectileComponent lifetime="%d" damage="%s" speed_min="%s" speed_max="%s" collide_with_world="%d" ' ..
        'collide_with_entities="%d" bounces_left="%d" bounce_energy="%s" on_collision_die="%d" friendly_fire="%d" ' ..
        'velocity_sets_rotation="%d" ground_collision_fx="0" die_on_low_velocity="0" />',
        o.lifetime, o.damage or 0, o.speed, o.speed_max or o.speed, b(o.world ~= false), b(o.entities ~= false),
        o.bounces or 0, o.bounce_energy or 0.5, b(o.die_on_collision ~= false), b(o.friendly_fire), b(o.rotate))
    
    if o.sprite then
        local size = CFG.sprite_size[o.sprite] or { 16, 16 }
        local scale = CFG.sprite_scale and CFG.sprite_scale[o.sprite] or 1.0
        
        if scale ~= 1.0 then
            -- THE FIX: Hide the sprite inside a child <Entity>. 
            -- The game engine won't see it when the root projectile dies, saving us from the giant background stamp bug!
            t[#t + 1] = '<Entity>'
            t[#t + 1] = string.format('<SpriteComponent image_file="%s%s.png" offset_x="%s" offset_y="%s" has_special_scale="1" special_scale_x="%s" special_scale_y="%s" />',
                SPR, o.sprite, size[1] / 2, size[2] / 2, scale, scale)
            t[#t + 1] = '</Entity>'
        else
            t[#t + 1] = string.format('<SpriteComponent image_file="%s%s.png" offset_x="%s" offset_y="%s" />',
                SPR, o.sprite, size[1] / 2, size[2] / 2)
        end
    end
    
    t[#t + 1] = string.format('<AudioComponent file="%s" event_root="%s" set_latest_event_position="1" />',
        DEFAULT_SOUND_BANK, DEFAULT_SOUND_ROOT)
    t[#t + 1] = lua_comp(o.kind, o.every)
    t[#t + 1] = '</Entity>'
    return table.concat(t, "\n")
end

local function generate_xml()
    write_xml("confetti_spark", projectile_xml{ name = "reco_confetti", kind = "confetti", lifetime = 300,
        damage = 0, speed = 120, speed_max = 280, world = false, friction = 3.0 })
    write_xml("bald_shot", projectile_xml{ name = "reco_bald_shot", kind = "bald", lifetime = 1500,
        damage = 67 / 25, speed = 25, sprite = "bald_shot", every = 3 })
    write_xml("celebratium_pixel", projectile_xml{ name = "reco_celebratium", kind = "celebratium", lifetime = 30,
        damage = 0, speed = 250, entities = false, die_on_collision = false })
    write_xml("cake", projectile_xml{ name = "reco_cake", kind = "cake", lifetime = 240, damage = 0,
        speed = 380, entities = false, bounces = 5, bounce_energy = 0.95, sprite = "cake" })
    write_xml("dunkbot", projectile_xml{ name = "reco_dunkbot", kind = "dunkbot", lifetime = 240, damage = 0,
        speed = 220, gravity = 300, entities = false, bounces = 3, bounce_energy = 0.5, sprite = "dunkbot" })
    write_xml("toobald_fx", '<Entity>' .. lua_comp("toobald", 3) .. '</Entity>')
    write_xml("sweat_fx",   '<Entity>' .. lua_comp("sweat", 4) .. '</Entity>')
end

---------------------------------------------------------------- dispatch
if RECO_SPELL_INIT then generate_xml() return end

local got, comp = pcall(GetUpdatedComponentID)
if got and comp ~= nil and comp ~= 0 and ComponentHasTag(comp, "reco_script") then run_script(comp) return end

if actions == nil then return end

---------------------------------------------------------------- gun mode (spell registration)
local function shoot(name)
    local path = GEN .. name .. ".xml"
    local ok, content = pcall(ModTextFileGetContent, path)
    if not ok or content == nil or content == "" then
        return
    end
    add_projectile(path)
end

local function spawn_script_entity(name, x, y, kind, state)
    local e = EntityCreateNew(name)
    EntitySetTransform(e, x, y)
    local v = EntityAddComponent2(e, "VariableStorageComponent", { name = "reco_gg", value_string = state })
    ComponentAddTag(v, "reco_gg")
    local l = EntityAddComponent2(e, "LuaComponent", { script_source_file = SELF, execute_every_n_frame = 1 })
    ComponentAddTag(l, "reco_script")
    ComponentAddTag(l, "reco_" .. kind)
    return e
end

local new_actions = {
    -- ===== 1. Confetti =====
    {
        id = "RHM_CONFETTI", name = "Confetti", description = "Happy birthday.",
        sprite = ICON .. "confetti.png",
        type = ACTION_TYPE_PROJECTILE, spawn_level = "1,2,3,4", spawn_probability = "0.5,0.5,0.4,0.3",
        price = 100, mana = 10,
        action = function()
            for _ = 1, CFG.confetti_count do shoot("confetti_spark") end
            c.spread_degrees = c.spread_degrees + 25
            c.fire_rate_wait = c.fire_rate_wait + 4
        end,
    },
    -- ===== 2. Bald Shot =====
    {
        id = "RHM_BALD_SHOT", name = "Bald Shot", description = "...",
        sprite = ICON .. "bald_shot.png",
        type = ACTION_TYPE_PROJECTILE, spawn_level = "3,4,5,6", spawn_probability = "0.2,0.2,0.2,0.2",
        price = 400, mana = 80,
        action = function()
            shoot("bald_shot")
            c.fire_rate_wait = c.fire_rate_wait + 600            
            current_reload_time = current_reload_time + 180      
        end,
    },
    -- ===== 3. tooBald =====
    {
        id = "RHM_TOOBALD", name = "tooBald", description = "......",
        sprite = ICON .. "toobald.png",
        type = ACTION_TYPE_MODIFIER, spawn_level = "1,2,3,4", spawn_probability = "0.3,0.3,0.3,0.3",
        price = 120, mana = 5,
        action = function()
            c.extra_entities = c.extra_entities .. GEN .. "toobald_fx.xml,"
            draw_actions(1, true)
        end,
    },
    -- ===== 4. Happy Party =====
    {
        id = "RHM_HAPPY_PARTY", name = "Happy Party", description = "Invite friends to party with you.",
        sprite = ICON .. "happy_party.png",
        type = ACTION_TYPE_UTILITY, spawn_level = "2,3,4,5", spawn_probability = "0.3,0.3,0.3,0.3",
        price = 250, mana = 40, max_uses = 1, never_unlimited = true,
        action = function()
            if reflecting then return end
            local _, px, py = shooter_info()
            play_default_sound(px, py)
            SetRandomSeed(GameGetFrameNum(), px + py)
            for _ = 1, CFG.party_hamis do
                local e = EntityLoad(CFG.hamis_entity, px + Random(-30, 30), py + Random(-22, 6))
                if e ~= nil and e ~= 0 then
                    local hp = CFG.party_hamis_hp / 25
                    local dm = EntityGetFirstComponent(e, "DamageModelComponent")
                    if dm ~= nil then
                        ComponentSetValue2(dm, "max_hp", hp)
                        ComponentSetValue2(dm, "hp", hp)
                    end
                    for _, lc in ipairs(EntityGetComponentIncludingDisabled(e, "LuaComponent") or {}) do
                        local sd = ComponentGetValue2(lc, "script_death")
                        if sd ~= nil and sd:find("drop_money", 1, true) then EntityRemoveComponent(e, lc) end
                    end
                end
            end
        end,
    },
    -- ===== 5. Celebratium Pixel =====
    {
        id = "RHM_CELEBRATIUM_PIXEL", name = "Celebratium Pixel", description = "Yay.",
        sprite = ICON .. "celebratium_pixel.png",
        type = ACTION_TYPE_PROJECTILE, spawn_level = "1,2,3,4", spawn_probability = "0.4,0.4,0.4,0.3",
        price = 150, mana = 5,
        action = function()
            shoot("celebratium_pixel")
            c.fire_rate_wait = c.fire_rate_wait + 30              
        end,
    },
    -- ===== 6. Friend =====
    {
        id = "RHM_FRIEND", name = "Friend", description = "Invites a local to celebrate your birthday.",
        sprite = ICON .. "friend.png",
        type = ACTION_TYPE_UTILITY, spawn_level = "1,2,3,4,5", spawn_probability = "0.3,0.3,0.3,0.3,0.3",
        price = 180, mana = 20,
        action = function()
            if reflecting then return end
            local player, px, py, ax, ay = shooter_info()
            play_default_sound(px, py)
            local best, best_d
            for _, e in ipairs(EntityGetInRadiusWithTag(px, py, CFG.friend_range, "enemy") or {}) do
                if e ~= player and EntityGetIsAlive(e) then
                    local ex, ey = EntityGetTransform(e)
                    local d = (ex - px) ^ 2 + (ey - py) ^ 2
                    if best == nil or d < best_d then best, best_d = e, d end
                end
            end
            if best ~= nil then
                local fx, fy = FindFreePositionForBody(px + ax * 30, py + ay * 30 - 4, 0, 0, 10)
                if fx == nil then fx, fy = px + ax * 30, py - 4 end
                EntityApplyTransform(best, fx, fy)
            end
        end,
    },
    -- ===== 7. Sweat =====
    {
        id = "RHM_SWEAT", name = "Sweat", description = "Oil up.",
        sprite = ICON .. "sweat.png",
        type = ACTION_TYPE_MODIFIER, spawn_level = "1,2,3,4", spawn_probability = "0.3,0.3,0.3,0.3",
        price = 250, mana = 20,
        action = function()
            c.extra_entities = c.extra_entities .. GEN .. "sweat_fx.xml,"
            draw_actions(1, true)
        end,
    },
    -- ===== 8. God Gamer =====
    {
        id = "RHM_GOD_GAMER", name = "God Gamer",
        description = "Are you a god gamer? If so, cast this spell. Coin flip.",
        sprite = ICON .. "god_gamer.png",
        type = ACTION_TYPE_UTILITY, spawn_level = "2,3,4,5,6", spawn_probability = "0.2,0.2,0.2,0.2,0.2",
        price = 300, mana = 30, max_uses = 2, never_unlimited = true,
        action = function()
            if reflecting then return end
            local _, px, py = shooter_info()
            play_default_sound(px, py)
            SetRandomSeed(GameGetFrameNum(), px + py)
            local win = Random(0, 1) == 1
            GamePrintImportant(win and "The gods acknowledge your skills" or "The gods do not endorse you", "")
            spawn_script_entity("reco_god_gamer", px, py, "godgamer",
                string.format("%s|%s|%s|%d|0", tostring(px), tostring(py), win and "win" or "lose", GameGetFrameNum()))
        end,
    },
    -- ===== 9. Cake Thrower =====
    {
        id = "RHM_CAKE_THROWER", name = "Cake Thrower", description = "Dunk is caked up.",
        sprite = ICON .. "cake_thrower.png",
        type = ACTION_TYPE_PROJECTILE, spawn_level = "1,2,3,4,5", spawn_probability = "0.4,0.4,0.4,0.3,0.3",
        price = 200, mana = 25,
        action = function()
    if reflecting then return end

    local _, px, py, ax, ay = shooter_info()
    emit_cake_projectile(
        px,
        py,
        px + ax * 380,
        py + ay * 380
    )

    c.fire_rate_wait = c.fire_rate_wait + 12
end,
    },
    -- ===== 10. Dunkbot 2.0 =====
    {
        id = "RHM_DUNKBOT", name = "Dunkbot 2.0",
        description = "Do onto the world what hath been done upon Dunkbot 2.0",
        sprite = ICON .. "dunkbot.png",
        type = ACTION_TYPE_PROJECTILE, spawn_level = "4,5,6", spawn_probability = "0.1,0.1,0.1",
        price = 500, mana = 70,
        action = function()
            if reflecting then return end
            local _, px, py, ax, ay = shooter_info()
            emit_dunkbot_projectile(
                px,
                py,
                px + ax * CFG.dunkbot_speed,
                py + ay * CFG.dunkbot_speed
            )
            c.fire_rate_wait = c.fire_rate_wait + 30
        end,
    },
}

for _, a in ipairs(new_actions) do
    a.sprite_unidentified = a.sprite
    table.insert(actions, a)
end