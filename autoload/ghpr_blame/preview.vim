let s:PREVIEW = {'bufnr' : -1, 'pr_num' : -1}

function! ghpr_blame#preview#create() abort
    return deepcopy(s:PREVIEW)
endfunction

function! s:_winnr() dict abort
    return bufwinnr(self.bufnr)
endfunction
let s:PREVIEW.winnr = function('s:_winnr')

function! s:_open(...) dict abort
    if a:0 > 0
        let split = a:1
    elseif winwidth(0) >= 160
        let split = 'botright vnew'
    else
        let split = 'botright new'
    endif
    execute split
    setlocal bufhidden=delete nobackup noswf nobuflisted buftype=nofile nonumber norelativenumber
    let self.bufnr = bufnr('%')
endfunction
let s:PREVIEW.open = function('s:_open')

" Returns whether it moved into other window
function! s:_enter() dict abort
    let w = bufwinnr(self.bufnr)
    if w != -1
        if w != winnr()
            execute w . 'wincmd w'
            return 1
        endif
        return 0
    endif
    call self.open()
    return 1
endfunction
let s:PREVIEW.enter = function('s:_enter')

function! s:_close() dict abort
    let w = bufwinnr(self.bufnr)
    if w == -1
        return
    endif
    if winnr() != w
        execute w . 'wincmd w'
    endif
    close!
    let self.bufnr = -1
    let self.pr_num = -1
endfunction
let s:PREVIEW.close = function('s:_close')

function! s:_reset() dict abort
    let moved = self.enter()
    silent %delete _
    if moved
        wincmd p
    endif
    let self.bufnr = -1
    let self.pr_num = -1
endfunction
let s:PREVIEW.reset = function('s:_reset')
