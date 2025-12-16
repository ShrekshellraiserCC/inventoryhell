return {
    type = "Screen",
    content = {
        {
            type = "Button",
            x = 1,
            y = "h",
            h = 1,
            w = 1,
            text = "$'\\27'$",
            key = "tab",
            on_click = "$tapi.back$"
        },
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
                    "w-16",
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
}
