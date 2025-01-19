-- TODO: Add support for justification to TODO markers
-- TODO: Recognize strings comments and allow for their formatting (python)
-- TODO: Add indentation level based on currently pointed line
-- TODO: Add visual mode formatting?
-- TODO: Correct number of whitespaces for before inline comment - e.g. python has 2 whitespaces
-- FIXME: Adjacent Multiline and Singleline comments will probably get merged together when wrapping a block
-- Implement guard against adding multiline comments when searching for adjacent nodes in singleline comment
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
local utils = require 'wrap.utils'
local rules = require 'wrap.rules'
local tr = vim.treesitter

local M = {}

-- Default config -@class (exact) _Config -@field line_width integer -@field rules Rules
local _config = {
    line_width = 40,
    rules = rules,
}

---@class (exact) Config
---@field line_width integer?
---@field rules Rules?

---Setup plugin config
---@param opts Config
function M.setup(opts)
    opts = opts or {}

    -- Runtime check of user-provided config
    local ft_rules = opts.rules
    if ft_rules ~= nil and not vim.tbl_isempty(ft_rules) then
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
                            ('Token `%s` (specified for %s:%s) must be a string!'):format(
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

    vim.api.nvim_create_user_command('Wrap', function(us_opts)
        local farg = us_opts.fargs[1]
        if farg == 'block' then
            M.wrap { block_only = true }
        elseif farg == 'comment' then
            M.wrap { block_only = false }
        else
            vim.notify(
                ('[wrap.nvim] `Wrap %s` is not a known command. Following subcommands are available: block, comment'):format(
                    farg
                ),
                vim.log.levels.ERROR
            )
        end
    end, { nargs = 1 })
end

--- @param fmtr MultiFormatter
--- @param com_lines string[]
--- @param lead_wtspcs string[]
local function wrap_multi_block(fmtr, com_lines, lead_wtspcs)
    local row_start, col_start, row_end, col_end = unpack(fmtr.init_node_range)
    -- Extract block pointed at by the cursor (or visual selection)
    vim.print(fmtr.rel_cur_row, fmtr.rel_v_row_end)
    local block_lines, left, right =
        fmtr:isolate_block(com_lines, fmtr.rel_cur_row, fmtr.rel_v_row_end)
    vim.print(com_lines, block_lines, left, right)
    if block_lines == nil then
        vim.notify(
            '[wrap.nvim] Selected line consists only of whitespaces',
            vim.log.levels.WARN
        )
        return
    end
    -- Rewrap (reformat) the block
    local block_text = utils.concatenate_lines(block_lines)
    local com_length = _config.line_width - #lead_wtspcs[fmtr.rel_cur_row]
    local wrapped_lines = fmtr:wrap(block_text, com_length)
    -- Merge the block into original comment lines
    com_lines, lead_wtspcs =
        fmtr:merge_block(com_lines, lead_wtspcs, wrapped_lines, left, right)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_block(com_lines, lead_wtspcs)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(
        fmtr.bufnr,
        row_start,
        col_start,
        row_end,
        col_end,
        buffer_lines
    )
end

--- @param fmtr SingleFormatter
local function wrap_single_block(fmtr)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(fmtr.init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes)
    -- Extract block pointed by the cursor
    local rel_cur_row = fmtr.cur_row - tr.get_node_range(com_nodes[1]) + 1
    -- TODO: Implement Visual selection
    -- local rel_v_row_end
    -- if v_row_end ~= nil then
    --     rel_v_row_end = v_row_end - tr.get_node_range(com_nodes[1]) + 1
    -- end
    local block_lines, left, right = fmtr:isolate_block(com_lines, rel_cur_row)
    if block_lines == nil then
        vim.notify(
            '[wrap.nvim] Selected line consists only of whitespaces',
            vim.log.levels.WARN
        )
        return
    end
    -- Rewrap (reformat) the block
    local com_text = utils.concatenate_lines(block_lines)
    local com_length = _config.line_width - fmtr.init_node_range[2]
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_lines(wrapped_lines, com_nodes[left])
    -- Replace buffer lines
    local block_row_start, _, _, _ = tr.get_node_range(com_nodes[left])
    local _, _, block_row_end, block_col_end = tr.get_node_range(com_nodes[right])
    vim.api.nvim_buf_set_text(
        fmtr.bufnr,
        block_row_start,
        0,
        block_row_end,
        block_col_end,
        buffer_lines
    )
end

---@param fmtr MultiFormatter
---@param com_lines string[]
local function wrap_multi_comment(fmtr, com_lines)
    local row_start, col_start, row_end, col_end = unpack(fmtr.init_node_range)
    -- Rewrap (reformat) the block
    local com_text = utils.concatenate_lines(com_lines)
    local com_length = _config.line_width - col_start
    local wrapped_lines = fmtr:wrap(com_text, com_length)
    table.insert(wrapped_lines, 1, '') -- Keep comment tokens on separate lines
    table.insert(wrapped_lines, #wrapped_lines + 1, '')
    -- Concatenate buffer lines
    local buffer_lines = fmtr:build_buf_whole(wrapped_lines)
    -- Replace buffer lines
    vim.api.nvim_buf_set_text(
        fmtr.bufnr,
        row_start,
        col_start,
        row_end,
        col_end,
        buffer_lines
    )
end

---@param fmtr SingleFormatter
local function wrap_single_comment(fmtr)
    -- Find all row-adjacent comment nodes
    local com_nodes = fmtr:find_adjacent_nodes(fmtr.init_node)
    -- Parse all found nodes
    local com_lines = fmtr:parse_block(com_nodes)
    local block_row_start, block_col_start, _, _ = tr.get_node_range(com_nodes[1])
    -- Rewrap (reformat) the block
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

---Wrap text in the node
---@param opts { block_only: boolean }
function M.wrap(opts)
    local block_only = opts.block_only

    local is_visual = vim.list_contains({ 'v', 'V', 'CTRL-V' }, vim.fn.mode())
    if not block_only and is_visual then
        vim.notify(
            '[wrap.nvim] Use `Wrap block` when in Visual mode',
            vim.log.levels.WARN
        )
        return
    end

    local cur_row, cur_col, v_row_end, v_col_end
    if is_visual then
        cur_row, cur_col = unpack(vim.fn.getpos 'v', 2, 3)
        v_row_end, v_col_end = unpack(vim.fn.getpos '.', 2, 3)

        -- If Visual selection was done from bottom up, swap start with end positions
        if v_row_end < cur_row or (v_row_end == cur_row and v_col_end < cur_col) then
            local temp_row, temp_col = cur_row, cur_col
            cur_row, cur_col = v_row_end, v_col_end
            v_row_end, v_col_end = temp_row, temp_col
        end

        -- Switch from (1,1) to (0,0) indexing
        cur_row, cur_col = cur_row - 1, cur_col - 1
        v_row_end, v_col_end = v_row_end - 1, v_col_end - 1
    else
        cur_row, cur_col = unpack(vim.fn.getpos '.', 2, 3)
        cur_row, cur_col = cur_row - 1, cur_col - 1 -- Switch from (0,1) to (0,0) indexing
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo.filetype
    local pointed_node, ft_rules, init_node, init_type

    -- Extract the node pointed at with the cursor
    tr.get_parser(bufnr):parse()
    pointed_node = tr.get_node { bufnr = bufnr, pos = { cur_row, cur_col } }
    if pointed_node == nil then
        vim.notify('[wrap.nvim] No Treesitter node under the cursor', vim.log.levels.WARN)
        return
    end
    -- Read filetype specific parsing rules
    ft_rules = utils.get_ft_rules(ft, _config.rules)
    if ft_rules == nil then
        vim.notify('[wrap.nvim] wrap.nvim does not support ' .. ft, vim.log.levels.WARN)
        return
    end
    -- Find a relevant node
    init_node, init_type = utils.find_node(pointed_node, ft_rules)
    if init_node == nil or init_type == nil then
        vim.notify('[wrap.nvim] Did not find a wrappable node', vim.log.levels.WARN)
        return
    end

    local init_text = tr.get_node_text(init_node, bufnr)
    local multi_tokens, single_tokens =
        utils.get_node_tokens(init_type, ft, _config.rules)

    -- Try parsing as a multiline comment
    local multi_fmtr = fmts.MultiFormatter:new {
        tokens = multi_tokens,
        filetype = ft,
        init_node = init_node,
        cur_row = cur_row,
        bufnr = bufnr,
        v_row_end = v_row_end,
    }
    local success, com_lines, lead_wtspcs = pcall(multi_fmtr.parse, multi_fmtr, init_text)
    if success then
        if block_only then
            wrap_multi_block(multi_fmtr, com_lines, lead_wtspcs)
        else
            wrap_multi_comment(multi_fmtr, com_lines)
        end
        return
    end

    -- Multiline failed to parse, must be single-line
    local single_fmtr = fmts.SingleFormatter:new {
        tokens = single_tokens,
        filetype = ft,
        init_node = init_node,
        cur_row = cur_row,
        bufnr = bufnr,
    }
    if block_only then
        wrap_single_block(single_fmtr)
    else
        wrap_single_comment(single_fmtr)
    end
end

return M
