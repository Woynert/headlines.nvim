local M = {}

M.namespace = vim.api.nvim_create_namespace "headlines_namespace"
local q = require "vim.treesitter.query"

local use_legacy_query = vim.fn.has "nvim-0.9.0" ~= 1

local parse_query_save = function(language, query)
    -- vim.treesitter.query.parse_query() is deprecated, use vim.treesitter.query.parse() instead
    local ok, parsed_query =
        pcall(use_legacy_query and vim.treesitter.query.parse_query or vim.treesitter.query.parse, language, query)
    if not ok then
        return nil
    end
    return parsed_query
end

M.config = {
    query = parse_query_save(
        "markdown",
        [[
            ((atx_heading
              (atx_h1_marker) @headline1
              (_) @1_heading_content))
            ((atx_heading
              (atx_h2_marker) @headline2
              (_) @2_heading_content))
            ((atx_heading
              (atx_h3_marker) @headline3
              (_) @3_heading_content))
            ((atx_heading
              (atx_h4_marker) @headline4
              (_) @4_heading_content))
            ((atx_heading
              (atx_h5_marker) @headline5
              (_) @5_heading_content))
            ((atx_heading
              (atx_h6_marker) @headline6
              (_) @6_heading_content))

            (thematic_break) @dash

            (fenced_code_block) @codeblock

            (block_quote_marker) @quote
            (block_quote (paragraph (inline (block_continuation) @quote)))
            (block_quote (paragraph (block_continuation) @quote))
            (block_quote (block_continuation) @quote)
        ]]
    ),
    headline_symbol = "»",
    headline_dash_symbol = "—",
    headline_dash_highlight = "Dash",

    dash_symbol = "-",
    dash_highlight = "Dash",

    headline_highlights = {
        "markdownH1",
        "markdownH2",
        "markdownH3",
        "markdownH4",
        "markdownH5",
        "markdownH6",
    },
}

M.make_reverse_highlight = function(name)
    local reverse_name = name .. "Reverse"

    if vim.fn.synIDattr(reverse_name, "fg") ~= "" then
        return reverse_name
    end

    local highlight = vim.fn.synIDtrans(vim.fn.hlID(name))
    local gui_bg = vim.fn.synIDattr(highlight, "bg", "gui")
    local cterm_bg = vim.fn.synIDattr(highlight, "bg", "cterm")

    if gui_bg == "" then
        gui_bg = "None"
    end
    if cterm_bg == "" then
        cterm_bg = "None"
    end

    vim.cmd(string.format("highlight %s guifg=%s ctermfg=%s", reverse_name, gui_bg or "None", cterm_bg or "None"))
    return reverse_name
end

M.setup = function(config)
    config = config or {}
    M.config = vim.tbl_deep_extend("force", M.config, config)

    -- tbl_deep_extend does not handle metatables
    for filetype, conf in pairs(config) do
        if conf.query then
            M.config[filetype].query = conf.query
        end
    end

    vim.cmd [[
        highlight default link Headline ColorColumn
        highlight default link CodeBlock ColorColumn
        highlight default link Dash LineNr
        highlight default link DoubleDash LineNr
        highlight default link Quote LineNr
    ]]

    vim.cmd [[
        augroup Headlines
        autocmd FileChangedShellPost,Syntax,TextChanged,InsertLeave,WinScrolled * lua require('headlines').refresh()
        augroup END
    ]]
end

local nvim_buf_set_extmark = function(...)
    pcall(vim.api.nvim_buf_set_extmark, ...)
end

local get_node_raw_text = function(node, bufnr)
    if use_legacy_query then
        return q.get_node_text(node, bufnr)
    else
        return vim.treesitter.get_node_text(node, bufnr)
    end
end

M.refresh = function()
    -- TODO: find a better way
    if vim.bo.filetype ~= "markdown" then
        return
    end

    local c = M.config
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(0, M.namespace, 0, -1)

    if not c or not c.query then
        return
    end

    local language = c.treesitter_language or vim.bo.filetype
    local language_tree = vim.treesitter.get_parser(bufnr, language)
    local syntax_tree = language_tree:parse()
    local root = syntax_tree[1]:root()
    local win_view = vim.fn.winsaveview()
    local left_offset = win_view.leftcol
    local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local width = wininfo.width - wininfo.textoff
    local last_fat_headline = -1
    local capture = ''

    for _, match, metadata in c.query:iter_matches(root, bufnr) do
        for id, node in pairs(match) do
            --prev_capture = capture
            capture = c.query.captures[id]
            local start_row, start_column, end_row, end_column =
                unpack(vim.tbl_extend("force", { node:range() }, (metadata[id] or {}).range or {}))

            if capture == "headline1" then
                -- top and bottom screen wide horizontal lines

                local screen_line = { { c.headline_dash_symbol:rep(width), c.headline_dash_highlight } }
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                    virt_lines_above = true,
                    virt_lines = { screen_line },
                })
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                    virt_lines = { screen_line },
                })

            elseif capture == "headline2" then
                -- bottom screen wide horizontal line

                local screen_line = { { c.headline_dash_symbol:rep(width), c.headline_dash_highlight } }
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                    virt_lines = { screen_line },
                })

            elseif capture == "1_heading_content" then

                -- get level from name

                local level = tonumber(string.sub(capture, 1, 1))
                local text_width = end_column - start_column
                local my_text = get_node_raw_text(node, bufnr)
                if end_column <= width then -- perfect fit

                    -- center header if H1

                    if level == 1 then

                        local reps = math.floor((width - text_width)/2)
                        my_text = (" "):rep(reps) .. my_text .. (" "):rep(width - text_width - reps)
                    else
                        my_text = my_text .. (" "):rep(width - text_width)
                    end

                    local virt_text = {{ my_text, c.headline_highlights[level] }}
                    
                    nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                        virt_text = virt_text,
                        virt_text_pos = "overlay",
                        virt_text_win_col = 0,
                    })

                end

            elseif capture == "dash" then
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                    virt_text = { { c.dash_symbol:rep(width), c.dash_highlight } },
                    virt_text_pos = "overlay",
                    hl_mode = "combine",
                })
            end
        end
    end
end

return M
