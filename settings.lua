data:extend ({
    {
        type = "int-setting",
        name = "creep-growth",
        setting_type = "runtime-global",
        default_value = 6,
        minimum_value = 1,
        maximum_value = 128,
    },
    {
        type = "int-setting",
        name = "creep-evolution-factor",
        setting_type = "runtime-global",
        default_value = 9,    -- human-scaled
        minimum_value = 0,    -- disabled
        maximum_value = 1000
    }
})
