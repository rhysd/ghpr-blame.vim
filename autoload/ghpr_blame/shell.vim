let s:P = ghpr_blame#vital().import('Async.Promise')

let s:JOB = {}
function! s:_on_close(channel) dict abort
    echo 'CLOSE!'
    for part in ['out', 'err']
        let buf = []
        while ch_status(a:channel, {'part' : part}) ==# 'buffered'
            let buf += [ch_read(a:channel, {'part' : part})]
        endwhile
        let self['std' . part] = join(buf, "\n")
    endfor
    call self.on_finish()
endfunction
let s:JOB.on_close = function('s:_on_close')

function! s:_on_exit(_, status) dict abort
    echo 'EXIT!'
    let self.exit_code = a:status
    call self.on_finish()
endfunction
let s:JOB.on_exit = function('s:_on_exit')

function! s:_on_finish() dict abort
    if !has_key(self, 'stdout') || !has_key(self, 'stderr') || !has_key(self, 'exit_code')
        return
    endif
    if self.exit_code != 0
        call self.reject(self.stderr)
    else
        call self.resolve(self.stdout)
    endif
endfunction
let s:JOB.on_finish = function('s:_on_finish')

function! ghpr_blame#shell#start(cmd) abort
    let j = deepcopy(s:JOB)
    echo j
    return s:P.new({resolve, reject ->
    \   extend(j, {
    \     'raw' : job_start(a:cmd, {
    \       'close_cb' : j.on_close,
    \       'exit_cb' : j.on_exit,
    \     }),
    \     'resolve' : resolve,
    \     'reject' : reject,
    \   })
    \ })
endfunction
