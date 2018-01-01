let s:V = vital#ghpr_blame#new()
function! ghpr_blame#vital() abort
    return s:V
endfunction

let s:H = s:V.import('Web.HTTP')

function! ghpr_blame#throw(msg) abort
    throw 'ghpr_blame: ' . a:msg
endfunction

function! ghpr_blame#warn(msg) abort
    echohl WarningMsg | echomsg 'ghpr_blame: ' . a:msg | echohl None
endfunction

function! ghpr_blame#error(msg) abort
    echohl ErrorMsg | echomsg 'ghpr_blame: ' . a:msg | echohl None
endfunction

function! ghpr_blame#show_pr_here() abort
    if !exists('b:ghpr') || !b:ghpr.started
        return
    endif
    call b:ghpr.show_pr_at(line('.'))
endfunction

function! ghpr_blame#start() abort
    if exists('b:ghpr')
        return
    endif
    let b:ghpr = ghpr_blame#app#new(expand('%:p'))
    call b:ghpr.start()
endfunction

function! ghpr_blame#quit() abort
    if !exists('b:ghpr')
        return
    endif
    call b:ghpr.quit()
    unlet b:ghpr
endfunction
