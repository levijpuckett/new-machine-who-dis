" easier escaping
inoremap jk <ESC>
inoremap kj <ESC>

" syntax highlighting
syntax on

" easier to reach this for leading
let mapleader = ","

" better autocomplete
set ignorecase
set smartcase

" show what we search for
set hlsearch

" tabs
set tabstop=4
set shiftwidth=4
set noexpandtab

" show the absolute number on the current line
set number

" ,w - open a new vertical split and switch to it
nnoremap <leader>w <C-w>v<C-w>l

" window navigation. ctl + [h,j,k,l] to move around windows
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" wrapping settings - wrap at 95, colour 95th column as a reminder.
set wrap
set textwidth=94
set formatoptions=ctqrn1
set colorcolumn=95
highlight colorcolumn ctermbg=235

" ... different when committing
filetype indent plugin on

