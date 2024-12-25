-- TODO: Add support for justification to TODO markers
-- TODO: Recognize strings comments and allow for their formatting (python)
-- TODO: Add indentation level based on currently pointed line
-- TODO: Add visual mode formatting?
-- FIXME: When wrapped line has a word which is shorted than available characters, it will loop endlessly and freeze nvim
-- FIXME: Multiline inline comments do not wrap correctly when first inline line is selected
-- x = 15; `Another multi-line comment with
--     wrapping that is written to
--         simulate a paragraph-style
--         explanation, where the content
--
--         wraps nicely. Tabs used foindentation and continuation
--         lines for additional styling or indentation.
--         `
local fmts = require 'wrap.fmts'
local temp = require 'utils' -- TODO: Temporary, delete
local utils = require 'wrap.utils'
local rules = require 'wrap.rules'
local p = temp.pprint
local tr = vim.treesitter

local M = {}

-- Default config
---@class (exact) Config
---@field line_width integer
---@field rules Rules
local _config = {
    line_width = 40,
    rules = rules,
}

---Setup plugin config
---@param opts Config
function M.setup(opts)
    opts = opts or {}

    -- Runtime check of user-provided config
    local ft_rules = opts.rules
    if ft_rules ~= nil then
        for ft, ft_rule in pairs(ft_rules) do
            for node_type, token_groups in pairs(ft_rule) do
                for _, token_group in ipairs(token_groups) do
                    assert(
                        #token_group == 1 or #token_group == 2,
                        'You can only provide 1 or 2 tokens in a single group - opening or opening/closing tokens'
                    )
                    for _, token in ipairs(token_group) do
                        assert(
                            type(token) == 'string',
                            ('Token %s (specified for %s:%s) must be a string!'):format(
                                token,
                                ft,
                                node_type
                            )
                        )
                    end
                end
            end
        end
    end

    _config = vim.tbl_deep_extend('force', _config, opts)
end

--- @param fmtr MultiFormatter
--- @param com_lines string[]
--- @param lead_wtspcs string[]
local function wrap_multi_paragraph(fmtr, com_lines, lead_wtspcs)
    local row_start, col_start, row_end, col_end = unpack(fmtr.init_node_range)
    -- Extract paragraph pointed by the cursor
    local paragraph_lines, left, right = fmtr:isolate_paragraph(com_lines, fmtr.rel_cur_y)
    if paragraph_lines == nil then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    -- Rewrap (reformat) the paragraph
    local paragraph_text = utils.concatenate_lines(paragraph_lines)
    local com_length = _config.line_width - #lead_wtspcs[fmtr.rel_cur_y]
    local wrapped_lines = fmtr:wrap(paragraph_text, com_length)
    -- Merge the paragraph into original comment lines
    com_lines, lead_wtspcs =
        fmtr:merge_paragraph(com_lines, lead_wtspcs, wrapped_lines, left, right)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_paragraph(com_lines, lead_wtspcs)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(fmtr.bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

--- @param fmtr SingleFormatter
local function wrap_single_paragraph(fmtr)
    local _, col_start, _, _ = unpack(fmtr.init_node_range)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(fmtr.init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes)
    -- Extract paragraph pointed by the cursor
    local rel_cur_y = fmtr.cur_y - tr.get_node_range(com_nodes[1]) + 1
    local paragraph_lines, left, right = fmtr:isolate_paragraph(com_lines, rel_cur_y)
    if paragraph_lines == nil then
        vim.notify 'Selected line consists only of whitespaces'
        return
    end
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(paragraph_lines)
    local com_length = _config.line_width - fmtr.init_node_range[2]
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, com_nodes[left])
    -- Replace buffer lines
    local paragraph_row_start, _, _, _ = tr.get_node_range(com_nodes[left])
    local _, _, paragraph_row_end, paragraph_col_end = tr.get_node_range(com_nodes[right])
    vim.api.nvim_buf_set_text(
        fmtr.bufnr,
        paragraph_row_start,
        0,
        paragraph_row_end,
        paragraph_col_end,
        buffer_lines
    )
end

---@param fmtr MultiFormatter
---@param com_lines string[]
local function wrap_multi_whole(fmtr, com_lines)
    local row_start, col_start, row_end, col_end = unpack(fmtr.init_node_range)
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    table.insert(wrapped_lines, 1, '') -- Keep comment tokens on separate lines
    table.insert(wrapped_lines, #wrapped_lines + 1, '')
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_whole(wrapped_lines)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(fmtr.bufnr, row_start, col_start, row_end, col_end, buffer_lines)
end

---@param fmtr SingleFormatter
local function wrap_single_whole(fmtr)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(fmtr.init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes)
    local block_row_start, block_col_start, _, _ = tr.get_node_range(com_nodes[1])
    -- Rewrap (reformat) the paragraph
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - block_col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, com_nodes[1])
    -- Replace buffer lines
    local _, _, block_row_end, block_col_end = tr.get_node_range(com_nodes[#com_nodes])
    vim.api.nvim_buf_set_text(
        fmtr.bufnr,
        block_row_start,
        0,
        block_row_end,
        block_col_end,
        buffer_lines
    )
end

function M.wrap(paragraph_only)
    paragraph_only = paragraph_only or false

    print ''
    print '-----------------'
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo.filetype
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local cur_y, cur_x = unpack(cur_pos)
    cur_y, cur_x = cur_y - 1, cur_x -- Switch from (1,0) to (0,0) indexing
    local pointed_node, init_types, init_node, init_type

    -- Extract the node pointed at with the cursor
    -- tr.get_parser(bufnr):parse()
    pointed_node = tr.get_node { bufnr = bufnr, pos = { cur_y, cur_x } }
    if pointed_node == nil then
        vim.notify 'No Treesitter node under the cursor'
        return
    end

    -- Read filetype specific parsing rules
    init_types = utils.get_custom_nodes(ft, _config.rules)
    if init_types == nil then
        vim.notify('wrap.nvim does not support ' .. ft)
        return
    end

    -- Find a relevant node
    init_node, init_type = utils.find_node(pointed_node, init_types)
    if init_node == nil or init_type == nil then
        vim.notify 'Did not find a node'
        return
    end

    local init_text = tr.get_node_text(init_node, bufnr)
    local multi_tokens, single_tokens = utils.get_node_tokens(init_type, ft, _config.rules)

    -- Try parsing as a multiline comment
    local multi_fmtr = fmts.MultiFormatter:new {
        tokens = multi_tokens,
        filetype = ft,
        init_node = init_node,
        cur_y = cur_y,
        bufnr = bufnr,
    }
    local success, com_lines, lead_wtspcs = pcall(multi_fmtr.parse, multi_fmtr, init_text)
    if success then
        if paragraph_only then
            wrap_multi_paragraph(multi_fmtr, com_lines, lead_wtspcs)
        else
            wrap_multi_whole(multi_fmtr, com_lines)
        end
        return
    end

    -- Multiline failed to parse, must be single-line
    local single_fmtr = fmts.SingleFormatter:new {
        tokens = single_tokens,
        filetype = ft,
        init_node = init_node,
        cur_y = cur_y,
        bufnr = bufnr,
    }
    if paragraph_only then
        wrap_single_paragraph(single_fmtr)
    else
        wrap_single_whole(single_fmtr)
    end
end

return M
