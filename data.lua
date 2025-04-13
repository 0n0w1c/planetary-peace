data:extend({
    {
        type = "shortcut",
        name = "planetary-peace-toggle",
        action = "lua",
        toggleable = true,
        icon = "__planetary-peace__/graphics/icons/planetary-peace.png",
        icon_size = 64,
        small_icon = "__planetary-peace__/graphics/icons/planetary-peace.png",
        small_icon_size = 64,
        associated_control_input = "planetary-peace-toggle-key"
    },
    {
        type = "custom-input",
        name = "planetary-peace-toggle-key",
        key_sequence = "CONTROL + P",
        consuming = "none"
    }
})
