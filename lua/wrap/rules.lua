---Table where each key is a TSNode type, and the value is a list of lists, each containing one or two tokens.
---@class Rules
---@field [string] string[][]
local rules = {
    c = {
        comment = {
            { '//' },
            { '/*', '*/' },
        },
    },
    lua = {
        comment = {
            { '--' },
            { [[--[[]], ']]' }, -- Escaped with long brackets
        },
    },
    python = {
        string = {
            { '"""', '"""' },
            { [[''']], [[''']] },
        },
        comment = { { '#' } },
    },
    javascript = {
        template_string = { { '`', '`' } },
        -- comment = {
        --     { '//' },
        --     { '/*', '*/' },
        -- },
    },
    go = {
        comment = {
            { '//' },
            { '/*', '*/' },
        },
    },
    java = {
        comment = {
            { '//' },
            { '/*', '*/' },
        },
    },
    cpp = {
        comment = {
            { '//' },
            { '/*', '*/' },
        },
    },
    ruby = {
        comment = { { '#' } },
    },
    html = {
        comment = { { '<!--', '-->' } },
    },
    css = {
        comment = { { '/*', '*/' } },
    },
    sh = {
        comment = { { '#' } },
    },
}

return rules
