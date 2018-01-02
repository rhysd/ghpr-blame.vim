let s:H = ghpr_blame#vital().import('Web.HTTP')

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
    " TODO: GHE support
    let ghpr.host = 'github.com'
    let ghpr.pr_cache = {}
    let ghpr.started = v:false
    return ghpr
endfunction

function! s:_build_git_cmd(args) dict abort
    let opts = join(map(copy(a:000), 's:shellescape(v:val)'), ' ')
    return 'cd ' . s:shellescape(self.dir) . ' && git ' . opts
endfunction
let s:GHPR.build_git_cmd = function('s:_build_git_cmd')

function! s:_git(...) dict abort
    let out = system(self.build_git_cmd(a:000))
    if v:shell_error
        call ghpr_blame#throw(printf("Git command '%s' failed: %s", cmd, out))
    endif
    return out
endfunction
let s:GHPR.git = function('s:_git')

function! s:_extract_slug() dict abort
    let out = self.git('config', '--get', 'remote.origin.url')
    let host = escape(self.host, '.')
    let m = matchlist(out, printf('^git@%s:\([^/]\+/[^/]\+\)\.git\n$', host))
    if empty(m)
        let m = matchlist(out, printf('^https://%s/\([^/]\+/[^/]\+\)\.git\n$', host))
    endif
    if empty(m)
        return ''
    endif
    return m[1]
endfunction
let s:GHPR.extract_slug = function('s:_extract_slug')

function! s:_blame() dict abort
    let lines = split(self.git('blame', '--first-parent', '--line-porcelain', self.file), "\n")
    let blames = []
    for line in lines
        let m = matchlist(line, '^\(\x\+\) \d\+ \d\+ \d\+$')
        if len(m) > 0
            let hash = m[1]
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

    let slug = self.extract_slug()
    if slug ==# ''
        call ghpr_blame#warn('Cannot get GitHub repository from')
        return
    endif
    let self.slug = slug

    let blames = self.blame()
    let self.blames = blames
    let self.started = v:true
    let self.prev_line = line('.')
    augroup plugin-ghpr-blame
        autocmd!
        autocmd CursorMoved <buffer> call <SID>on_cursor_moved()
    augroup END
    let mapping = get(g:, 'ghpr_show_pr_mapping', '<CR>')
    if mapping !=# ''
        execute 'nnoremap <buffer><silent>' . mapping . ' :<C-u>call ghpr_blame#show_pr_here()<CR>'
    endif
endfunction
let s:GHPR.start = function('s:_start')

function! s:move_to_preview() abort
    if &l:previewwindow
        return
    endif
    let winnr = winnr()
    try
        wincmd P
    catch /^Vim\%((\a\+)\)\=:E441/
        if winwidth(0) >= 160
            let split = 'vnew'
        else
            let split = 'new'
        endif
        execute 'botright' split
        setlocal previewwindow bufhidden=delete nobackup noswf nobuflisted buftype=nofile filetype=markdown
    endtry
endfunction

function! s:_show_pr_at(line) dict abort
    let idx = a:line - 1
    if !self.started || idx >= (len(self.blames)-1) || !has_key(self.blames[idx], 'pr')
        call ghpr_blame#warn('no PR is related to this line')
        return
    endif

    let num = self.blames[idx].pr
    if exists('b:ghpr_pr_num') && b:ghpr_pr_num == num
        return
    endif

    if !has_key(self.pr_cache, num)
        let pr = self.fetch_pr(num)
        let self.pr_cache[num] = pr
    else
        let pr = self.pr_cache[num]
    endif

    call s:move_to_preview()
    call self.render_pr(pr)
    wincmd p
endfunction
let s:GHPR.show_pr_at = function('s:_show_pr_at')

function! s:_fetch_pr(num) dict abort
    let headers = {'Accept' : 'application/vnd.github.v3+json'}
    if get(g:, 'ghpr_github_auth_token', '') !=# ''
        let headers.Authorization = 'token ' . g:ghpr_github_auth_token
    endif
    let url = printf('https://api.%s/repos/%s/pulls/%d', self.host, self.slug, a:num)
    let response = s:H.request({
        \ 'url' : url,
        \ 'headers' : headers,
        \ 'method' : 'GET',
        \ 'client' : ['curl', 'wget'],
        \ })
    if !response.success
        call ghpr_blame#error(printf('API request failed with status %s: %s', response.status, response, statusText))
        return {}
    endif
    return json_decode(response.content)
endfunction
let s:GHPR.fetch_pr = function('s:_fetch_pr')

function! s:_render_pr(pr) dict abort
    let b:ghpr_pr_num = a:pr.number
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
    let lines += split(a:pr.body, "\n")
    call append(0, lines)
    normal! gg0
endfunction
let s:GHPR.render_pr = function('s:_render_pr')

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

function! s:_quit() dict abort
    try
        wincmd P
        close
    catch /^Vim\%((\a\+)\)\=:E441/
    endtry

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
