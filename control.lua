local modname = "creeper"

local DEVELOP = false

-- This isn't pollution per se, but it's an easy way to think of
-- it during the calculations.
local CREEP_POLLUTION_PER_TICK = 0.0001 / 3600
local CREEP_TICKS = 13
local DEFERRED_PER_INTERVAL = 3
local DEFERRED_TICKS = 17
local EVO_TICKS = 61
local POLLUTION_POWER = 1.2
local THETA_OFFSET = math.pi / 4
local TILES_PER_INTERVAL = 16
local UNIT_WAIT_TICKS = 60 * 3


function table.copy (tbl)
    local tbl_type = type (tbl)
    local copy
    if tbl_type == 'table' then
        copy = {}
        for key, value in pairs (tbl) do
            copy[key] = value
        end
    else
        copy = tbl
    end
    return copy
end


function first_time()
    -- Register our command.
    commands.add_command (
        "creepolution",
        "Display evolution accounting for creep.",
        command_creepolution
    )

    -- Indexed by spawner as each has it's own direction
    -- and creep count to track.
    global.creep_state = {}
    global.evolution_factor_by_creep = 0
    global.work_index = nil

    -- We lazily track the chunks with pollution, using events
    -- to guess if we should turn our Sauron gaze upon them.
    -- For instance, when units are built, their position is
    -- a mostly accurate guess for the chunk that has a spawner.
    -- And spawner locations, since they spawn creep, are good
    -- places to check for pollution.
    global.deferred_chunks = {}
    global.evolution_chunks = {}

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
end


script.on_init (first_time)
script.on_load (function()
    commands.add_command (
        "creepolution",
        "Display evolution accounting for creep.",
        command_creepolution
    )
end)


script.on_nth_tick (CREEP_TICKS, function (event)
    --[[--
    States are:
      - wait - batching unit spawns
      - search - walking the creep looking for drop-off point (TILES_PER_TICK)
      - spawn - drop-off point located, spawn all neighbor creeps
    --]]--

    local creep
    if global.work_index then
        creep = global.creep_state[global.work_index]
    end

    if creep then
        local fini = false

        if not creep.surface.valid then
            fini = true

        elseif creep.state == "search" then
            -- Find a spot to begin searching for free creep spots.
            creep_iterative_search (creep)

            if creep.spawn_position then
                creep.state = "spawn"
            elseif not creep.search_position then
                -- No searches to continue
                fini = true
            end

        elseif creep.state == "spawn" then
            -- Search out local tiles to drop a creep.
            local creeps
            if creep.spawn_position then
                creeps = spawn_creep (
                        creep.surface,
                        creep.spawn_position,
                        creep.creep_count
                )
            end

            if creeps and creep.surface.valid then
                -- Let someone else do some work.
                global.work_index = nil

                -- This is just like `on_entity_spawned`.
                creep.state = "wait"
                creep.creep_count = creeps
                creep.search_tick = event.tick + UNIT_WAIT_TICKS
            else
                -- Done with this one.
                fini = true
            end

        else
            -- This is wrong. Just delete it and move on with your life.
            fini = true
        end

        if fini then
            global.creep_state[global.work_index] = nil
            global.work_index = nil
        end

    else
        -- There isn't an active search/spawn going so check the
        -- spawners to see if any are primed to creep.

        -- Bind locally.
        local global_creep_state = global.creep_state

        for index, state in pairs (global_creep_state) do
            if not state.surface.valid then
                global_creep_state[index] = nil

            elseif state.state == "wait" then
                if state.search_tick and event.tick >= state.search_tick then
                    if init_search_params (state) then
                        state.state = "search"
                        global.work_index = index

                        -- Only process one at a time.
                        break
                    else
                        global_creep_state[index] = nil
                    end
                end
            end
        end
    end
end)


script.on_nth_tick (DEFERRED_TICKS, function (event)
    if not global.deferred_chunks then return end

    -- The big hit in time is counting tiles. That's what
    -- will be counted as "processed" in Camp Four.
    local deferred_processed = 0
    for key, chunk in pairs (global.deferred_chunks) do
        local surface = game.surfaces[chunk.surface_index]
        local position = chunk.chunk_position.area.left_top

        if surface and surface.valid then
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
end)


script.on_nth_tick (EVO_TICKS, function (event)
    if not game.map_settings.pollution.enabled then
        -- Respect the difficulty settings. If pollution isn't
        -- enabled, it won't modify the evolution from it.
        global.evolution_chunks = {}
        return
    end

    local sg = settings.global
    local cef = sg["creep-evolution-factor"].value
    local is_bonus_checked = sg["creep-evolution-pollution-bonus"].value

    if cef > 0 then
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
            local surface = game.surfaces[chunk.chunk.surface_index]
            if surface and surface.valid then
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
        pollution = pollution * EVO_TICKS

        -- Based on the creep evolution factor setting (scaled down from
        -- human form), calculate how much evolution factor from creep.
        -- Before applied to the base of 1 - evo.
        local evo_c_pollution = cef / 100000 * pollution

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
end)


script.on_event (defines.events.on_biter_base_built, function (event)
    -- The only purpose for processing this event is to add a little
    -- variation to the perfect ellipses that Krastorio creates.
    local entity = event.entity
    if entity and entity.valid and entity.type == "unit_spawner" then
        spawner_event (event.tick, entity)
    end
end)


script.on_event (defines.events.on_entity_died, function (event)
    local entity = event.entity
    if entity and entity.valid then
        -- For evolution calculation.
        defer_chunk {entity.surface, entity.position}
    end
end, {{ filter = "type", type = "unit-spawner" }})


script.on_event (defines.events.on_entity_spawned, function (event)
    local spawner = event.entity
    if spawner and spawner.valid then
        spawner_event (event.tick, spawner)
    end
end)


function on_remove_tile (event)
    local surface = game.surfaces[event.surface_index]
    for _, tile in pairs (event.tiles) do
        if tile.old_tile.name == "kr-creep" then
            -- For evolution calculation.
            defer_chunk {surface, tile.position}
        end
    end
end


script.on_event (defines.events.on_player_mined_tile, on_remove_tile)
script.on_event (defines.events.on_robot_mined_tile, on_remove_tile)


script.on_event (defines.events.on_player_selected_area, function (event)
    if event.item == "kr-creep-collector" then
        -- The collector may be too far or have no creep, but that's
        -- okay. Once the deferred area is processed, it'll be resolved.
        local surface = event.surface
        if surface and surface.valid then
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
end)


function chunk_key (params)
    local surface_index
    local pos_x, pos_y

    if params.chunk then
        surface_index = params.chunk.surface_index
        pos_x = params.chunk.chunk_position.x
        pos_y = params.chunk.chunk_position.y
    elseif params.entity then
        surface_index = params.entity.surface.index
        pos_x = math.floor (params.entity.position.x / 32)
        pos_y = math.floor (params.entity.position.y / 32)
    else
        print (modname, "chunk_key: invalid params", serpent.line (params))
        __crash()
    end

    return table.concat ({ surface_index, ":", pos_x, ":", pos_y })
end


function command_creepolution (args)
    local player = game.get_player (args.player_index)
    local f = game.forces.enemy
    if player and f then
        local evo = f.evolution_factor or 0
        local evo_t = f.evolution_factor_by_time or 0
        local evo_p = f.evolution_factor_by_pollution or 0
        local evo_s = f.evolution_factor_by_killing_spawners or 0
        local evo_c = global.evolution_factor_by_creep or 0

        -- Prevent divide-by-zero (w/ episilon)
        local evo_parts = evo_t + evo_p + evo_s + evo_c
        if evo_parts <= 0.00001 then
            evo_parts = 1
        end

        player.print (string.format (
                "Evolution factor: %0.04f. (Time %d%%) "
                        .. "(Pollution %d%%) (Spawner kills %d%%) "
                        .. "(Creep %d%%) ",
                evo,
                evo_t * 100 / evo_parts,
                evo_p * 100 / evo_parts,
                evo_s * 100 / evo_parts,
                evo_c * 100 / evo_parts
        ))

        local creep_in_pollution = 0
        for _, chunk in pairs (global.evolution_chunks) do
            creep_in_pollution = creep_in_pollution + chunk.creep
        end

        player.print (string.format (
                "Creepolution factor: %0.08f (polluted creep %d)",
                evo_c,
                creep_in_pollution
        ))

        -- And debug stats to the log.
        local evo_string
        if game.map_settings.pollution.enabled then
            evo_string = string.format ("%0.08f", evo_c)
        else
            evo_string = "disabled"
        end

        print (string.format ("%d %s: monitored chunks=%d, "
                .. "deferred chunks=%d, evolution factor=%s, "
                .. "creep=%d, work items=%d, work index=%d",
                args.tick,
                modname,
                table_size (global.evolution_chunks or {}),
                table_size (global.deferred_chunks or {}),
                evo_string,
                creep_in_pollution,
                table_size (global.creep_state or {}),
                global.work_index or 0
        ))
    end
end


function creep_iterative_search (creep)
    local surface = creep.surface
    creep.spawn_position = nil

    if not surface.valid then
        creep.search_position = nil
        return
    end

    local creep_position
    local x = creep.search_position.x
    local y = creep.search_position.y
    local dx = creep.theta.dx
    local dy = creep.theta.dy
    local iterations = 0
    local position

    repeat
        x = x + dx
        y = y + dy

        position = { x = x, y = y }

        local tile = filter_tile (surface.get_tile (position))
        if not tile then
            -- Abort the iterative search.
            position = nil
        elseif tile.name ~= "kr-creep" then
            creep_position = tile.position
        end

        iterations = iterations + 1
    until creep_position or iterations >= TILES_PER_INTERVAL or not position

    if creep_position then
        creep.spawn_position = creep_position
    else
        -- This will either be the save point to continue next time,
        -- or it will be nil indicating to stop completely.
        creep.search_position = position
    end
end


function creep_search_position (surface, position)
    if not surface.valid then return nil end

    local creeps = surface.find_tiles_filtered {
        position = position,
        radius = 16,
        name = "kr-creep",
    }
    local creeps_len = table_size (creeps)

    if creeps_len == 0 then
        return nil
    end

    local stats_loops = 0
    local search_position
    local rnd = math.random (1, creeps_len)
    for i=rnd, rnd + creeps_len do
        local tile = filter_tile (creeps[i % rnd + 1])
        if tile then
            search_position = tile.position
            break
        end
        stats_loops = stats_loops + 1
    end

    return search_position
end


function defer_chunk (params)
    setmetatable (params, { __index={ chunk_position=nil }})
    local surface = params[1] or params.surface
    local position = params[2] or params.position
    local chunk_position = params[3] or params.chunk_position

    if not (surface and surface.valid) then return end
    if not (position or chunk_position) then
        print (modname, "defer_chunk: bad params", serpent.line (params))
        __crash()
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

    global.deferred_chunks[chunk_key {chunk=chunk}] = chunk
end


function filter_tile (tile)
    if not tile then return nil end
    if not tile.valid then return nil end
    if tile.collides_with ("player-layer") then return nil end

    return tile
end


function init_creep_state (unit_number)
    global.creep_state[unit_number] = {
        state = "wait",
        creep_count = 0,
    }
end


function init_search_params (creep)
    local surface = creep.surface
    local position = creep.position

    creep.search_position = creep_search_position (surface, position)
    if not creep.search_position then
        return false
    end

    -- Figure out the target area the creep should grow toward.
    local chunks = surrounding_chunk_pollutions (surface, position)
    local target_chunk = weighted_random_pollution (chunks)

    local theta = target_chunk.theta

    -- Randomize the angle (within an arc) to search toward.
    local theta_min = theta - THETA_OFFSET
    theta = theta_min + THETA_OFFSET * math.random()

    local dx = math.cos (theta)
    local dy = -math.sin (theta)  -- y-axis goes down

    -- Path to search for free tiles.
    creep.theta = { dx = dx, dy = dy }
    return true
end


function spawn_creep (surface, position, creeps)
    if not surface.valid then return nil end

    local offsets = {
        {-1, -1}, {0, -1}, {1, -1},
        {-1,  0}, {0,  0}, {1,  0},
        {-1,  1}, {0,  1}, {1,  1}
    }
    local tiles = {}

    -- Bind locally.
    local surface_get_tile = surface.get_tile

    local function find_free_tiles (find_pos)
        -- Used to track if we've found at least one drop-off
        -- in a full cycle. If we haven't, we abort wholesale
        -- because we may have wandered into the middle of an
        -- area that just wastes time finding nothing.
        local found_tile = true

        -- Bind locally.
        local math_random = math.random
        local table_concat = table.concat

        while creeps > 0 and found_tile do
            found_tile = false

            local dir = math_random (1, 9)
            for i = dir, dir+9 do
                local off = offsets[i % 9 + 1]
                local pos = { x = find_pos.x + off[1], y = find_pos.y + off[2] }

                local pt_key = table_concat ({pos.x, ":", pos.y})
                if not tiles[pt_key] then
                    local tile = filter_tile (surface_get_tile (pos))
                    if tile and tile.name ~= "kr-creep" then
                        tiles[pt_key] = {
                            name = "kr-creep",
                            position = tile.position
                        }

                        find_pos = tile.position
                        creeps = creeps - 1
                        found_tile = true

                        break
                    end
                end
            end
        end
    end

    find_free_tiles (position)

    local creep_tiles = {}
    local spawned = 0
    for _, tile in pairs (tiles) do
        -- For evolution calculation.
        defer_chunk {surface, tile.position}

        table.insert (creep_tiles, tile)
        spawned = spawned + 1
    end

    surface.set_tiles (creep_tiles)

    -- If we were able to find space for some, then requeue the leftovers
    -- so it tries again.
    if spawned > 0 and creeps > 0 then
        return creeps
    end
end


function spawner_event (tick, spawner)
    -- REQUIRES: valid spawner
    local unit_number = spawner.unit_number

    if not global.creep_state[unit_number] then
        init_creep_state (unit_number)
    end

    local creep = global.creep_state[unit_number]

    -- In all states, when a unit spawns, the creep count can increase.
    creep.surface = spawner.surface
    creep.position = spawner.position

    local spawn = math.random (1, settings.global["creep-growth"].value)
    creep.creep_count = creep.creep_count + spawn
    if not creep.search_tick then
        creep.search_tick = tick + UNIT_WAIT_TICKS
    end

    -- For evolution calculation. Even though when we get to spawn
    -- the creep, we also `defer_chunks`, we do it here in case
    -- the creep patch spans boundaries from where this spawner is.
    defer_chunk {spawner.surface, spawner.position}

end


function surrounding_chunk_pollutions (surface, position)
    -- REQUIRES: valid surface

    local chunks = {}
    local p = table.copy (position)

    -- Bind locally.
    local math_pi = math.pi
    local surface_get_pollution = surface.get_pollution

    -- defines.direction.northwest
    p.x = p.x - 32
    p.y = p.y - 32
    chunks[1] = {
        pollution = surface_get_pollution (p),
        theta=3 * math_pi / 4
    }

    -- defines.direction.north
    p.x = p.x + 32
    chunks[2] = {
        pollution = surface_get_pollution (p),
        theta = math_pi / 2
    }

    -- defines.direction.northeast
    p.x = p.x + 32
    chunks[3] = {
        pollution = surface_get_pollution (p),
        theta = math_pi / 4
    }

    -- defines.direction.east
    p.y = p.y + 32
    chunks[4] = {
        pollution = surface_get_pollution (p),
        theta = 0
    }

    -- defines.direction.west
    p.x = p.x - (32 * 2)  -- skipping over this "position" chunk
    chunks[5] = {
        pollution = surface_get_pollution (p),
        theta = math_pi
    }

    -- defines.direction.southwest
    p.y = p.y - 32
    chunks[6] = {
        pollution = surface_get_pollution (p),
        theta = 5 * math_pi / 4
    }

    -- defines.direction.south
    p.x = p.x + 32
    chunks[7] = {
        pollution = surface_get_pollution (p),
        theta = 3 * math_pi / 2
    }

    -- defines.direction.southeast
    p.x = p.x + 32
    chunks[8] = {
        pollution=surface_get_pollution (p),
        theta = 7 * math_pi / 4
    }

    return chunks
end


function weighted_random_pollution (chunks)
    local fudge = table_size (chunks) / 1.0

    -- Bind locally.
    local math_pow = math.pow

    local function scaling (what)
        -- Moar weight!
        return math_pow (what+1, POLLUTION_POWER) + fudge
    end

    local factor = 0
    for _, chunk_data in ipairs (chunks) do
        factor = factor + scaling (chunk_data.pollution)
    end

    local random_value = math.random()
    local weight = 0
    for _, chunk_data in ipairs (chunks) do
        weight = weight + scaling (chunk_data.pollution)
        if random_value <= weight / factor then
            return chunk_data
        end
    end
end
