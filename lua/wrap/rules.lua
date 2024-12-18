local rules = {
    c = {
        single = { '//' },
        multi = { '/*', '*/' },
    },
    lua = {
        single = { '--' },
        multi = { [[--[[]], ']]' },
    },
    python = {
        single = { '#' },
        multi = nil,
    },
    javascript = {
        single = { '//' },
        multi = { '/*', '*/' },
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
