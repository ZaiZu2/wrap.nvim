set rtp+=.
set rtp+=./deps/plenary.nvim/
set rtp+=./deps/nvim-treesitter/
set rtp+=./deps/mini.nvim/
lua << EOF
require('mini.test').setup()
EOF

runtime! plugin/nvim-treesitter.lua
runtime! plugin/plenary.vim
