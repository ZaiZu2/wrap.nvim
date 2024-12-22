-- TODO: Add support for justification to TODO markers
-- TODO: Recognize strings comments and allow for their formatting (python)
-- FIXME: When wrapped line has a word which is shorted than available characters, it will loop endlessly and freeze nvim

local fmts = require 'wrap.fmts'
local temp = require 'utils' -- TODO: Temporary, delete
local utils = require 'wrap.utils'
local p = temp.pprint

local M = {}

local _config = {
    line_width = 40,
}

local tr = vim.treesitter

function M.setup(config)
    config = config or {}
    _config = vim.tbl_deep_extend('force', _config, config)
end

local function wrap(com_text, com_length)
    local wrapped_lines, _ = {}, nil
    local com_split_end = 1 --- @type integer?
    local com_split_start = 0 --- @type integer?

    local is_final_substr = false
    -- Iterate over `comment`, cutting chunks out of it and building lines out of it
    while not is_final_substr do
        com_text = string.sub(com_text, com_split_start + com_split_end, -1)
        -- Skip over leading whitspaces first
        _, com_split_start = string.find(com_text, '^%s*')
        if com_split_start == nil then
            com_split_start = 1
        else
            com_split_start = com_split_start + 1
        end

        -- Find limits of a new line, accounting for comment length available left
        local line_start = com_split_start
        local line_end
        if line_start + com_length > #com_text then
            line_end = #com_text
            is_final_substr = true
        else
            line_end = line_start + com_length
        end

        -- Substring a new line
        local substring = string.sub(com_text, line_start, line_end)
        if not is_final_substr then
            -- Find if the new line is not splitting a word in a middle
            -- If it does, find the closest whitespace to the left of that word
            com_split_end, _ = string.find(substring, '%s*%S*$')
            if com_split_end == nil then -- Text occupies a full line width
                com_split_end = com_length
            -- TODO: Line might consist of only whitespaces (?), this is not handled here
            else
                com_split_end = com_split_end - 1
            end
            substring = string.sub(substring, 1, com_split_end)
        end

        table.insert(wrapped_lines, substring)
    end
    return wrapped_lines
end

function M.wrap()
    local bufnr = vim.api.nvim_get_current_buf()
    local cur_win = vim.api.nvim_get_current_win()

    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local cur_y, cur_x = unpack(cur_pos)
    cur_y, cur_x = cur_y - 1, cur_x -- Switch from (1,0) to (0,0) indexing

    -- Extract the node pointed at with the cursor and find the comment
    tr.get_parser(bufnr):parse()
    local init_node = tr.get_node { bufnr = bufnr, pos = { cur_y, cur_x } }
    init_node = utils.find_node(init_node, 'comment')
    if init_node == nil then
        vim.notify 'Did not find a comment node'
        return
    end

    local init_row_start, init_col_start, init_row_end, _ = tr.get_node_range(init_node)
    local init_text = tr.get_node_text(init_node, bufnr)

    local multi_fmtr = fmts.MultiFormatter:new(vim.bo.filetype)
    -- Try parsing as a multiline comment
    local success, com_lines = pcall(multi_fmtr.parse, multi_fmtr, init_text)
    if success then
        -- Extract paragraph pointed by the cursor
        local rel_cur_y = cur_y - init_row_start + 1
        local paragraph_lines, left, right = multi_fmtr:isolate_paragraph(com_lines, rel_cur_y)
        if paragraph_lines == nil then
            vim.notify 'Selected line consists only of whitespaces'
            return
        end
        -- Rewrap (reformat) the paragraph
        local com_text = table.concat(paragraph_lines, ' ')
        local com_length = _config.line_width - init_col_start
        local wrapped_lines = wrap(com_text, com_length)
        -- Merge the paragraph into original comment lines
        local merged_lines = multi_fmtr:merge_paragraph(com_lines, wrapped_lines, left, right)
        -- Replace buffer lines
        local buffer_lines = multi_fmtr:build_buf_lines(merged_lines, init_col_start)
        local row_start, row_end = init_row_start, init_row_end
        vim.api.nvim_buf_set_lines(bufnr, row_start, row_end + 1, true, buffer_lines)
        -- vim.api.nvim_win_set_cursor(cur_win, { rstart + 1, cur_x })
    else -- Multiline didn't match, must be single-line
        local single_fmtr = fmts.SingleFormatter:new(vim.bo.filetype)
        -- Find all row-adjacent comment nodes
        local com_nodes = single_fmtr:find_adjacent_nodes(init_node, bufnr)
        p { com_nodes = com_nodes }
        -- Parse all found nodes
        com_lines = single_fmtr:parse_block(com_nodes, bufnr)
        local com_text = table.concat(com_lines, ' ')
        -- Rewrap (reformat) the paragraph
        local com_length = _config.line_width - init_col_start - #(single_fmtr.symbols[1] .. ' ')
        local wrapped_lines = wrap(com_text, com_length)
        local buffer_lines = single_fmtr:build_buf_lines(wrapped_lines, init_col_start)
        -- Replace buffer lines
        local block_start, _, _, _ = tr.get_node_range(com_nodes[1])
        local _, _, block_end, _ = tr.get_node_range(com_nodes[#com_nodes])
        vim.api.nvim_buf_set_lines(bufnr, block_start, block_end + 1, true, buffer_lines)
        -- vim.api.nvim_win_set_cursor(cur_win, { rstart + 1, cur_x })
    end
end

return M
