_ENV = _ENV --[[@as SSDTermPluginENV]]

_ENV.tapi.register_screen("tasks", {
    type = "Screen",
    content = {
        _ENV.back_button_template(),
        {
            type = "Dropdown",
            x = 1,
            y = 1,
            w = 10,
            h = 1,
            value = "$task_category$",
            options = { "Local", "Server" }
        },
        {
            type = "Table",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            list = "$tasks$",
            columns = {
                {
                    "id",
                    "3",
                    "ID"
                },
                {
                    "name",
                    "w-17",
                    "Name"
                },
                {
                    "count",
                    "6",
                    "Count"
                },
                {
                    "running",
                    "7",
                    "Active"
                }
            },
        }
    }
})
