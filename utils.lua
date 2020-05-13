local util = require "util"


--[[ Generic utility functions ]]--

util.compare_key_value_table = function (t1, t2)
    if table_size (t1) ~= table_size (t2) then return false end
    for k1, v1 in pairs (t1) do
        if t2[k2] ~= v1 then return false end
    end
    return true
end


util.crash = function (...)
    print (...)
    __crash()
end


util.insert_keyed_table = function (tbl, key, value)
    if tbl[key] == nil then
        tbl[key] = { value }
    else
        table.insert (tbl[key], value)
    end
end



util.update_event_filters = function (event_filters)
    -- TODO: Test what you get back if an event is registered
    -- versus not registered. This is because if a naked event
    -- is registered and someone adds a filter, we want to discard it.

    -- Only useful for implicit "or".
    for event, filters in pairs (event_filters) do
        local new_filters = util.table.deepcopy (filters)
        local curr_filters = script.get_event_filter (event) or {}

        for _, curr_filter in pairs (curr_filters) do
            for _, filter in pairs (filters) do
                if not util.compare_key_value_table (curr_filter, filter) then
                    table.insert (new_filters, curr_filter)
                end
            end
        end

        script.set_event_filter (event, new_filters)
    end
end


--[[ Mod-specific utility functions ]]--

util.modname = "creeper"

util.chunk_key = function (params)
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
        util.crash (util.modname, "chunk_key: bad params", serpent.line (params))
    end

    return surface_index, ":", pos_x, ":", pos_y
end


util.filter_tile = function (tile)
    if not tile then return nil end
    if not tile.valid then return nil end
    if tile.collides_with ("player-layer") then return nil end

    return tile
end


util.filter_spawner = function (entity)
    if not entity then return nil end
    if not entity.valid then return nil end
    if entity.type ~= "unit-spawner" then return nil end
    -- Rampant has proxy spawners
    if string.match (entity.name, "proxy") then return nil end

    return entity
end


util.filter_surface = function (surface, no_virus_check)
    if not surface then return nil end
    if not surface.valid then return nil end
    if not no_virus_check
            and global.surface_viruses
            and global.surface_viruses[surface.index]
    then
        return nil
    end

    return surface
end


util.position_key = function (entity)
    -- REQUIRES: valid entity
    return entity.surface.index .. ":"
            .. entity.position.x .. ":"
            .. entity.position.y
end


return util
