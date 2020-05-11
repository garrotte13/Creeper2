local util = require "utils"


local CREEP_POLLUTION_PER_TICK = 0.0001 / 3600
local DEFERRED_PER_INTERVAL = 3
local DEFERRED_NTH_TICKS = 17
local EVO_NTH_TICKS = 67


-- Cached setting values.
local evo_factor = 0
local is_bonus_checked = false


-- Local binds.
local filter_surface = util.filter_surface
local filter_spawner = util.filter_spawner


local defer_chunk = function (params)
    setmetatable (params, { __index={ chunk_position=nil }})
    local surface = params[1] or params.surface
    local position = params[2] or params.position
    local chunk_position = params.chunk_position

    if not filter_surface (surface) then return end
    if not (position or chunk_position) then
        util.crash (modname, "defer_chunk: bad params", serpent.line (params))
    end

    if position then
        chunk_position = {
            x = math.floor(position.x / 32),
            y = math.floor(position.y / 32)
        }
    end

    local left_top = {
        x = chunk_position.x * 32,
        y = chunk_position.y * 32
    }

    local right_bottom = {
        x = left_top.x + 32,
        y = left_top.y + 32
    }

    local area = {
        left_top = left_top,
        right_bottom = right_bottom
    }

    local chunk = {
        surface_index = surface.index,
        chunk_position = {
            x = chunk_position.x,
            y = chunk_position.y,
            area = area
        }
    }

    global.deferred_chunks[util.chunk_key {chunk=chunk}] = chunk
end


local queue_deferrals = function (event)
    -- Chances are there's creep near where this event happend.

    local entity = event.entity
    if entity.valid then
        if entity.type == "unit-spawner" then
            entity = filter_spawner (entity)
        end

        if entity then
            defer_chunk {event.entity.surface, event.entity.position}
        end
    end
end


local on_player_selected_area = function (event)
    if event.item == "kr-creep-collector" then
        -- The collector may be too far or have no creep, but that's
        -- okay. Once the deferred area is processed, it'll be resolved.
        local surface = filter_surface (event.surface)
        if surface then
            local chunk_left_top = {
                x = math.floor (event.area.left_top.x / 32),
                y = math.floor (event.area.left_top.y / 32)
            }
            local chunk_right_bottom = {
                x = math.floor (event.area.right_bottom.x / 32),
                y = math.floor (event.area.right_bottom.y / 32)
            }
            for x = chunk_left_top.x, chunk_right_bottom.x do
                for y = chunk_left_top.y, chunk_right_bottom.y do
                    defer_chunk {surface, chunk_position={ x = x, y = y }}
                end
            end
        end
    end
end


local on_remove_tile = function (event)
    local surface = filter_surface (game.surfaces[event.surface_index])
    if not surface then return end

    for _, tile in pairs (event.tiles) do
        if tile.old_tile.name == "kr-creep" then
            -- For evolution calculation.
            defer_chunk {surface, tile.position}
        end
    end
end


local on_runtime_settings = function (event)
    if event.setting_type == "runtime-global" then
        if event.setting == "creep-evolution-factor" then
            evo_factor = settings.global[event.setting].value
        elseif event.setting == "creep-evolution-pollution-bonus" then
            is_bonus_checked = settings.global[event.setting].value
        end
    end
end


local on_deferred_nth_tick = function (event)
    -- The big hit in time is counting tiles. That's what
    -- will be counted as "processed" in Camp Four.
    local deferred_processed = 0
    for key, chunk in pairs (global.deferred_chunks) do
        local surface = filter_surface (game.surfaces[chunk.surface_index])
        local position = chunk.chunk_position.area.left_top

        if surface then
            local pollution = surface.get_pollution (position)
            if pollution > 0 then
                -- We need to interrogate this chunk and add it to
                -- the list of chunks to be monitored.
                local creep = surface.count_tiles_filtered {
                    name="kr-creep",
                    area=chunk.chunk_position.area
                }

                if creep > 0 then
                    global.evolution_chunks[key] = {
                        chunk = chunk,
                        creep = creep
                    }
                end

                deferred_processed = deferred_processed + 1
            end
        end

        -- It's either been elevated or isn't worth looking at.
        global.deferred_chunks[key] = nil

        if deferred_processed >= DEFERRED_PER_INTERVAL then
            break
        end
    end
end


local on_evo_nth_tick = function (event)
    if not game.map_settings.pollution.enabled then
        -- Respect the difficulty settings. If pollution isn't
        -- enabled, it won't modify the evolution from it.
        global.evolution_chunks = {}
        return
    end

    if evo_factor > 0 then
        -- This applies evolution to enemy forces, even though the lore
        -- of the creep is that it's spawner controlled, which implies
        -- specific forces and whatnot. But since the creep is just a
        -- tile and not associated w/ any spawner in specific, we'll
        -- just wing it for simplicity.

        local evo_c_previous = global.evolution_factor_by_creep or 0

        -- Bind locally.
        local evolution_chunks = global.evolution_chunks
        local math_max = math.max
        local math_log10 = math.log10

        -- How much psuedo-pollution generated per tick based on how
        -- many creep is dotting the landscape.
        local creep_in_pollution = 0
        for key, chunk in pairs (evolution_chunks) do
            local surface = filter_surface (game.surfaces[chunk.chunk.surface_index])
            if surface then
                -- Once it makes it into this list, there were creep.
                -- Creep won't change (unlike pollution) unless it goes
                -- back through the deferral list.
                local position = chunk.chunk.chunk_position.area.left_top
                local pollution = surface.get_pollution (position)
                if pollution > 0 then
                    local bonus_coefficient = 1

                    -- If the user wants this, evolution factor will
                    -- be higher for creep in higher pollution. This is
                    -- accomplished by creating a faux count of creeps.
                    if is_bonus_checked then
                        bonus_coefficient = math_max (1, math_log10 (pollution))
                    end

                    creep_in_pollution = creep_in_pollution
                            + (chunk.creep * bonus_coefficient)
                else
                    -- No need to monitor this anymore. Now, pollution
                    -- may float back into this chunk w/ creep, but
                    -- it will no longer be accounted until an event
                    -- happens within that chunk.
                    evolution_chunks[key] = nil
                end
            else
                evolution_chunks[key] = nil
            end
        end

        -- Approximation since we are not accurately tracking
        -- when we first observed creepiness.
        local pollution = CREEP_POLLUTION_PER_TICK * creep_in_pollution

        -- And then account for how many ticks elapsed since last calc.
        pollution = pollution * EVO_NTH_TICKS

        -- Based on the creep evolution factor setting (scaled down from
        -- human form), calculate how much evolution factor from creep.
        -- Before applied to the base of 1 - evo.
        local evo_c_pollution = evo_factor / 10000 * pollution

        -- Only updating the enemy as they are the ones with creep.
        local f = game.forces.enemy
        if f and f.valid then
            local evo = f.evolution_factor or 0
            local evo_c_delta = (1 - evo) * evo_c_pollution

            f.evolution_factor = evo + evo_c_delta

            local evo_c = evo_c_previous + evo_c_delta
            global.evolution_factor_by_creep = evo_c
        end
    end
end


local lib = {}

-- Exports
lib.defer_chunk = defer_chunk


lib.events = {
    [defines.events.on_biter_base_built] = queue_deferrals,
    [defines.events.on_entity_died] = queue_deferrals,
    [defines.events.on_entity_spawned] = queue_deferrals,
    [defines.events.on_player_mined_tile] = on_remove_tile,
    [defines.events.on_robot_mined_tile] = on_remove_tile,
    [defines.events.on_runtime_mod_setting_changed] = on_runtime_settings,
    [defines.events.on_player_selected_area] = on_player_selected_area,
}

lib.event_filters = {
    [defines.events.on_entity_died] = {
        { filter = "type", type = "unit" },
        { filter = "type", type = "unit-spawner" }
    },
}


lib.on_nth_tick = {
    [DEFERRED_NTH_TICKS] = on_deferred_nth_tick,
    [EVO_NTH_TICKS] = on_evo_nth_tick,
}


-- Called on new game.
-- Called when added to exiting game.
lib.on_init = function()
    -- Cache the settings.
    evo_factor = settings.global["creep-evolution-factor"].value
    is_bonus_checked = settings.global["creep-evolution-pollution-bonus"].value

    -- We lazily track the chunks with pollution, using events
    -- to guess if we should turn our Sauron gaze upon them.
    -- For instance, when spawners are built, their position is
    -- a mostly accurate guess for the chunk that has a spawner.
    -- And spawner locations, since they spawn creep, are good
    -- places to check for pollution.
    global.deferred_chunks = {}
    global.evolution_chunks = {}
    global.evolution_factor_by_creep = 0

    -- Walk all the surfaces and their chunks to figure out if
    -- there's stuff we should be monitoring now.
    for _, surface in pairs (game.surfaces) do
        if surface and surface.valid then
            -- Bind locally.
            local surface_is_chunk_generated = surface.is_chunk_generated
            local surface_get_pollution = surface.get_pollution

            for chunk in surface.get_chunks() do
                if surface_is_chunk_generated (chunk) then
                    -- We have chunks, but `get_pollution` is by position.
                    local pollution = surface_get_pollution (chunk.area.left_top)
                    if pollution > 0 then
                        defer_chunk {surface, chunk_position=chunk}
                    end
                end
            end
        end
    end

    -- The chunks of which we need to calculate pollution from creep.
    global.deferred_chunks = {}
    util.update_event_filters (lib.event_filters)
end


-- Not called when added to existing game.
-- Called when loaded after saved in existing game.
lib.on_load = function()
    -- Cache the settings.
    evo_factor = settings.global["creep-evolution-factor"].value
    is_bonus_checked = settings.global["creep-evolution-pollution-bonus"].value

    util.update_event_filters (lib.event_filters)
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
                "%s (pollution): %s -> %s",
                modname, old_version, new_version
        ))

        if old_version > "0.0.0" and new_version == "1.0.2" then
            for _, player in pairs (game.players) do
                local setting = settings.get_player_settings (player)
                local old = setting["creep-evolution-factor"].value
                local new = math.min (old * 10, 1000)
                setting["creep-evolution-factor"] = { value = new }
            end
        end
    end
end

return lib
