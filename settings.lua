data:extend ({
    {
        type = "int-setting",
        name = "creep-growth",
        setting_type = "runtime-global",
        default_value = 21,
        minimum_value = 1,
        maximum_value = 128,
        order = "a"
    },
    {
        type = "int-setting",
        name = "creep-evolution-factor",
        setting_type = "runtime-global",
        default_value = 9,    -- human-scaled
        minimum_value = 0,    -- disabled
        maximum_value = 1000,
        order = "b",
    },
    {
        type = "bool-setting",
        name = "creep-evolution-pollution-bonus",
        setting_type = "runtime-global",
        default_value = true,
        order = "c"
    }
})
