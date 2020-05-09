function add_create_entity (stream_string)
    local stream = data.raw.stream[stream_string]
    local stream_action = stream.action

    for _, action in pairs (stream_action) do
        for _, target_effects in pairs (action.action_delivery.target_effects) do
            if type (target_effects) == "table"
                    and target_effects.type == "create-fire"
                    and target_effects.entity_name == "fire-flame"
            then
                target_effects.trigger_created_entity = true
                goto done
            end
        end
    end
    ::done::
end


add_create_entity ("handheld-flamethrower-fire-stream")
add_create_entity ("flamethrower-fire-stream")

-- Default tank flamethrower won't trigger the event because it
-- doesn't leave a sticker, it just burninates the trees to the ground.
--add_create_entity ("tank-flamethrower-fire-stream")
