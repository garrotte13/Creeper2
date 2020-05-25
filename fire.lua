-- TODO: See about spreading from trees. Unfortunately, an event doesn't
-- TODO:   trigger when trees are damaged by fire, unlike other entities.
-- TODO:   Will probably need to modify prototype to create_entity

-- TODO: See about nuclear bombs and other "fire" sources lighting
-- TODO:   creep on fire. Or maybe just remove creep in its path.

-- TODO: Start a slow re-growth of grasses where the creep burned

-- TODO: Auto-target creep with flame turrets

local util = require "utils"


local CREEPER_FLAMES = {
    "creeper-flame-1",
    "creeper-flame-2",
    "creeper-flame-3",
    "creeper-flame-4",
}
local CREEPER_TILE = "creeper-landfill"

local FLAME_NTH_TICKS = 19
-- XXX: Are both needed? Is the initial vs. post delta noticeable?
local SPREAD_DELAY = { 300, 180 }
local SPREAD_N_DELAY = { 240, 240 }
local SPREAD_LIMIT = { 100, 1000 }


-- Cached setting values.
local burnination = true
local wildfires = false


-- Local binds.
local math_random = math.random
local filter_tile = util.filter_tile
local filter_surface = util.filter_surface
local position_key = util.position_key


local FlameEntity = function (entity)
    local flame = {}
    setmetatable (flame, { __index = entity })
    flame.index = position_key (entity)

    return flame
end


local filter_flame = function (entity)
    if not (entity and entity.valid) then return nil end
    if not filter_surface (entity.surface, true) then return nil end
    if entity.type ~= "fire" then return nil end

    return FlameEntity (entity)
end


local when_spread = function (whence, how)
    local parts
    local coeffecient = 1

    if how then
        parts = SPREAD_N_DELAY
    else
        parts = SPREAD_DELAY
    end

    return whence + math_random (parts[1], parts[1] + parts[2])
end


local on_trigger_created_entity = function (event)
    if not burnination then return end

    local flame = filter_flame (event.entity)
    if not flame then return end

    local surface = flame.surface
    local tile = filter_tile (surface.get_tile (flame.position))
    if tile and tile.name == "kr-creep" then
        surface.set_tiles ({
            { name = CREEPER_TILE, position = tile.position }
        })

        local force = flame.force

        -- XXX: This doesn't work. It's as if the effect is
        -- XXX: something else, but I cannot "find" it to remove it.
        flame.destroy()

        -- Replace it with ours since it is on creep.
        local entity = surface.create_entity {
            name = CREEPER_FLAMES[1],
            position = tile.position,
            force = force
        }

        local new_flame = FlameEntity (entity)

        local flame_info = {
            create_tick = event.tick,
            flame = new_flame,
            seed_index = new_flame.index,
            spawned_flames = 0,
            spread_tick = when_spread (event.tick)
        }
        global.active_flames[new_flame.index] = flame_info
        util.insert_keyed_table (
                global.by_tick, flame_info.spread_tick, new_flame.index
        )

        local coefficient = 1
        if wildfires then
            coefficient = 10
        end

        global.spread_limits[new_flame.index] = math_random (
                SPREAD_LIMIT[1],
                SPREAD_LIMIT[2] * coefficient
        )
    end
end


local spread_flame = function (tick, flame_info, flame_count)
    -- REQUIRES: valid flame/surface

    -- Bind locally.
    local table_insert = table.insert

    local surface = flame_info.flame.surface
    local surface_create_entity = surface.create_entity

    local surrounding_creep = surface.find_tiles_filtered {
        name = "kr-creep",
        position = flame_info.flame.position,
        radius = 2.5
    }

    local found_creep = table_size (surrounding_creep)
    local seed_index = flame_info.seed_index
    flame_count = math.min (found_creep, flame_count)

    local new_flames = {}
    local random_offset = math_random (0, found_creep)

    while flame_count > 0 do
        local tile_index = (flame_count + random_offset) % found_creep + 1
        local position = surrounding_creep[tile_index].position
        position.x = position.x + math_random() / 2
        position.y = position.y + math_random() / 2

        local entity = surface_create_entity {
            name = CREEPER_FLAMES[math_random (2, 4)],
            position = position,
            force = flame_info.flame.force
        }

        if entity then
            local flame = FlameEntity (entity)
            local how = flame_info.spawned_flames > 0

            table_insert (new_flames, {
                create_tick = tick,
                flame = flame,
                seed_index = seed_index,
                spawned_flames = 0,
                spread_tick = when_spread (tick, how)
            })

            flame_info.spawned_flames = flame_info.spawned_flames + 1
        end

        flame_count = flame_count - 1
    end

    return new_flames, found_creep - table_size (new_flames)
end


local on_flame_nth_tick = function (event)
    if not burnination then return end

    -- Bind locally.
    local table_insert = table.insert
    local active_flames = global.active_flames
    local by_tick = global.by_tick
    local spread_limits = global.spread_limits

    -- Table that contains tables of new flames that were generated.
    local new_flames = {}

    local tick = event.tick
    for t = tick - FLAME_NTH_TICKS + 1, tick do
        local now_flame_indices = by_tick[t] or {}
        for _, index in pairs (now_flame_indices) do
            local flame_info = active_flames[index]
            if not flame_info then goto continue end

            local flame = flame_info.flame

            local spread_limit = spread_limits[flame_info.seed_index]
            if not spread_limit or spread_limit <= 0 then
                active_flames[index] = nil
                spread_limits[flame_info.seed_index] = nil
            elseif not filter_flame (flame) then
                active_flames[index] = nil
            else
                local spread_count = 1
                if wildfires then
                    spread_count = 2
                end

                local flames, remaining_tiles = spread_flame (
                        tick,
                        flame_info,
                        spread_count
                )

                flame_info.spread_tick = when_spread (tick, true)
                util.insert_keyed_table (
                        by_tick,
                        flame_info.spread_tick,
                        flame_info.flame.index
                )

                if flames then
                    table_insert (new_flames, flames)

                    local remaining = spread_limit - table_size (flames)
                    spread_limits[flame_info.seed_index] = remaining
                end

                if remaining_tiles == 0 then
                    -- No need to monitor this. We still need the
                    -- `spread_limits` if this was the original flame.
                    active_flames[index] = nil
                end
            end
            ::continue::
        end
        -- All of these for this tick has been processed.
        by_tick[t] = nil
    end

    -- Finalize all the spread flames, killing off the creep, and
    -- setting them up in the global tables.
    local replacement_by_surface = {}

    for _, flames in pairs (new_flames) do
        for _, flame_info in pairs (flames) do
            local flame = flame_info.flame

            local surface_index = flame.surface.index
            local landfill = { name = CREEPER_TILE, position = flame.position }

            util.insert_keyed_table (
                    replacement_by_surface,
                    surface_index,
                    landfill
            )

            active_flames[flame.index] = flame_info
            util.insert_keyed_table (
                    by_tick, flame_info.spread_tick, flame.index
            )
        end
    end

    -- Nothing left to monitor.
    if table_size (active_flames) == 0 then
        global.spread_limits = {}
    end

    for surface_index, landscape_tiles in pairs (replacement_by_surface) do
        local surface = game.surfaces[surface_index]
        if surface and surface.valid then
            surface.set_tiles (landscape_tiles)
        end
    end
end


local on_runtime_settings = function (event)
    if event.setting_type == "runtime-global" then
        if event.setting == "creep-destroyed-by-fire" then
            burnination = settings.global[event.setting].value
        elseif event.setting == "creep-wildfires" then
            wildfires = settings.global[event.setting].value
        end
    end
end


local lib = {}

lib.events = {
    [defines.events.on_runtime_mod_setting_changed] = on_runtime_settings,
    [defines.events.on_trigger_created_entity] = on_trigger_created_entity,
}

lib.on_nth_tick = {
    [FLAME_NTH_TICKS] = on_flame_nth_tick,
}


local cache_settings = function()
    burnination = settings.global["creep-destroyed-by-fire"].value
    wildfires = settings.global["creep-wildfires"].value
end


-- Called on new game.
-- Called when added to exiting game.
lib.on_init = function()
    cache_settings()

    global.active_flames = {}
    global.by_tick = {}

    -- Indexed by the seed flame index. Used to track how many more
    -- flames can be spawned by it and its descendants.
    global.spread_limits = {}
end


-- Not called when added to existing game.
-- Called when loaded after saved in existing game.
lib.on_load = function()
    cache_settings()
end


-- Not called on new game.
-- Called when added to existing game.
lib.on_configuration_changed = function (config)
    local modname = util.modname
    local creeper
    if config and config.mod_changes then
        creeper = config.mod_changes[modname]
    end

    if creeper then
        local old_version = creeper.old_version or "0.0.0"
        local new_version = creeper.new_version or "0.0.0"

        print (string.format (
                "%s (fire): %s -> %s",
                modname, old_version, new_version
        ))

        if new_version == "1.0.3" then
            cache_settings()

            global.active_flames = {}
            global.by_tick = {}
            global.spread_limits = {}
        end
    end
end


return lib