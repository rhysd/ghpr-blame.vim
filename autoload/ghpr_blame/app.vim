let s:is_windows = has('win32') || has('win64')
if s:is_windows
  function! s:shellescape(...) abort
    try
      let shellslash = &shellslash
      set noshellslash
      return call('shellescape', a:000)
    finally
      let &shellslash = shellslash
    endtry
  endfunction
else
  let s:shellescape = function('shellescape')
endif

let s:GHPR = {}
function! ghpr_blame#app#new(fname) abort
    let ghpr = deepcopy(s:GHPR)
    let ghpr.file = a:fname
    let ghpr.dir = fnamemodify(a:fname, ':p:h')
    let ghpr.pr_cache = {}
    let ghpr.started = v:false
    let ghpr.bufnr = bufnr('%')
    return ghpr
endfunction

function! s:_git(...) dict abort
    let opts = join(map(copy(a:000), 's:shellescape(v:val)'), ' ')
    let cmd = 'cd ' . s:shellescape(self.dir) . ' && git ' . opts
    let out = system(cmd)
    if v:shell_error
        call ghpr_blame#throw(printf("Git command '%s' failed: %s", cmd, out))
    endif
    return out
endfunction
let s:GHPR.git = function('s:_git')

function! s:_extract_slug() dict abort
    let out = self.git('config', '--get', 'remote.origin.url')
    return ghpr_blame#slug#from_url(out)
endfunction
let s:GHPR.extract_slug = function('s:_extract_slug')

function! s:_blame() dict abort
    let lines = split(self.git('blame', '--first-parent', '--line-porcelain', self.file), "\n")
    let blames = []
    for line in lines
        let m = matchlist(line, '^\(\x\+\) \d\+ \(\d\+\) \d\+$')
        if len(m) > 0
            let hash = m[1]
            let lnum = str2nr(m[2])
            let delta = (lnum - 1) - len(blames)
            while delta > 0
                let blames += [current]
                let delta -= 1
            endwhile
            let current = {'hash' : hash}
            let blames += [current]
            continue
        endif
        if stridx(line, 'summary ') == 0
            let current.summary = line[strlen('summary '):]
            let m = matchlist(current.summary, '^Merge \%(pull request\|PR\) \#\(\d\+\) from ')
            if len(m) > 0
                let current.pr = m[1] + 0
            endif
        endif
    endfor
    return blames
endfunction
let s:GHPR.blame = function('s:_blame')

function! s:_start() dict abort
    if &l:buftype =~# 'nofile\|help\|quickfix' || self.file ==# ''
        call ghpr_blame#error('Invalid file for running blame')
        return
    endif

    try
        let slug = self.extract_slug()
    catch
        call ghpr_blame#warn('Cannot get GitHub repository from')
        return
    endtry
    let self.slug = slug

    let blames = self.blame()
    let self.blames = blames
    let self.prev_line = line('.')
    augroup plugin-ghpr-blame
        autocmd!
        if get(g:, 'ghpr_show_pr_in_message', 0)
            autocmd CursorMoved <buffer> call <SID>on_cursor_moved()
        endif
        autocmd BufEnter <buffer> call <SID>on_buf_enter()
    augroup END
    let mapping = get(g:, 'ghpr_show_pr_mapping', '<CR>')
    if mapping !=# ''
        execute 'nnoremap <buffer><silent>' . mapping . ' :<C-u>call ghpr_blame#show_pr_here()<CR>'
    endif

    let l = line('.')
    let self.pr_numbers = ghpr_blame#preview#create()
    let self.old_scrollbind = &l:scrollbind
    setlocal scrollbind
    call self.pr_numbers.open('leftabove vnew')
    let self.nums_win_width = self.render_pr_nums(l)
    wincmd p
    if l != line('.')
        execute l
    endif
    syncbind

    let self.pr_preview = ghpr_blame#preview#create()
    let self.started = v:true
endfunction
let s:GHPR.start = function('s:_start')

function! s:_show_pr_at(line) dict abort
    let idx = a:line - 1
    if !self.started || idx >= (len(self.blames)-1) || !has_key(self.blames[idx], 'pr')
        call ghpr_blame#warn('no PR is related to this line')
        return
    endif

    let num = self.blames[idx].pr
    if !has_key(self.pr_cache, num)
        echo 'Fetching pull request #' . num . '...'
        let pr = self.slug.fetch_pr(num)
        let self.pr_cache[num] = pr
    else
        let pr = self.pr_cache[num]
    endif

    let moved = self.pr_preview.enter()
    call self.render_pr(pr)
    if moved
        wincmd p
    endif
endfunction
let s:GHPR.show_pr_at = function('s:_show_pr_at')

function! s:_render_pr(pr) dict abort
    let b:ghpr_pr_num = a:pr.number
    let b:ghpr_bufnr = self.bufnr
    silent %delete _
    let lines = [
    \   a:pr.number . ': ' . a:pr.title,
    \   '===========',
    \   printf('[#%s](%s)', a:pr.number, a:pr.html_url),
    \   printf('[@%s](%s)', a:pr.user.login, a:pr.user.html_url),
    \   'Merged: ' . a:pr.merged_at,
    \   '-----------',
    \   '',
    \ ]
    let lines += split(substitute(a:pr.body, "\r", '', 'g'), "\n")
    call append(0, lines)
    setlocal filetype=markdown
    normal! gg0
endfunction
let s:GHPR.render_pr = function('s:_render_pr')

function! s:_render_pr_nums(lnum) dict abort
    let b:ghpr_bufnr = self.bufnr
    let numbers = []
    let max_num = -1
    for b in self.blames
        if has_key(b, 'pr')
            let numbers += ['#' . b.pr]
            if b.pr > max_num
                let max_num = b.pr
            endif
        else
            let numbers += ['']
        endif
    endfor
    augroup plugin-ghpr-blame
        autocmd BufUnload <buffer> call ghpr_blame#quit()
    augroup END
    if max_num == -1
        return 0
    endif
    call append(0, numbers)
    setlocal nowrap
    let width = float2nr(log10(max_num)) + 3
    execute 'vertical' 'resize' width
    execute a:lnum
    setlocal scrollbind
    return width
endfunction
let s:GHPR.render_pr_nums = function('s:_render_pr_nums')

function! s:on_cursor_moved() abort
    if !exists('b:ghpr') || !b:ghpr.started
        return
    endif
    let l = line('.')
    if b:ghpr.prev_line == l
        return
    endif
    let b:ghpr.prev_line = l
    let idx = l - 1
    if idx < len(b:ghpr.blames) && has_key(b:ghpr.blames[idx], 'pr')
        echo '#' . b:ghpr.blames[idx].pr
    else
        redraw!
    endif
endfunction

function! s:on_buf_enter() abort
    if !exists('b:ghpr') || !b:ghpr.started
        return
    endif
    let winnr = b:ghpr.pr_numbers.winnr()
    if winnr == -1
        return
    endif
    let width = b:ghpr.nums_win_width
    if winwidth(winnr) == width
        return
    endif
    let moved = b:ghpr.pr_numbers.enter()
    execute 'vertical' 'resize' width
    if moved
        wincmd p
    endif
endfunction

function! s:_quit() dict abort
    call self.pr_preview.close()
    call self.pr_numbers.close()
    let &l:scrollbind = self.old_scrollbind
    autocmd! plugin-ghpr-blame
    let mapping = get(g:, 'ghpr_show_pr_mapping', '<CR>')
    if mapping !=# ''
        try
            execute 'nunmap ' . mapping
        catch /^Vim\%((\a\+)\)\=:E31/
        endtry
    endif
endfunction
let s:GHPR.quit = function('s:_quit')
