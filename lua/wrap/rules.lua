---@type Rules
local rules = {
    c = {
        single = { '//' },
        multi = { '/*', '*/' },
    },
    lua = {
        single = { '--' },
        multi = { [[--[[]], ']]' }, -- Escaped with long brackets
    },
    python = {
        -- single = { '#' },
        -- multi = nil,
        custom = {
            string = {
                { '""""', '""""' },
                { [[''']], [[''']] },
            },
            comment = { { '#' } },
        },
    },
    javascript = {
        -- single = { '//' },
        -- multi = { '/*', '*/' },
        custom = {
            template_string = { { '`', '`' } },
            comment = {
                { '//' },
                { '/*', '*/' },
            },
        },
    },
    go = {
        single = { '//' },
        multi = { '/*', '*/' },
    },
    java = {
        single = { '//' },
        multi = { '/*', '*/' },
    },
    cpp = {
        single = { '//' },
        multi = { '/*', '*/' },
    },
    ruby = {
        single = { '#' },
        multi = nil,
    },
    html = {
        single = nil,
        multi = { '<!--', '-->' },
    },
    css = {
        single = nil,
        multi = { '/*', '*/' },
    },
    sh = {
        single = { '#' },
        multi = nil,
    },
}

return rules
