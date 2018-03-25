let s:H = ghpr_blame#vital().import('Web.HTTP')

let s:SLUG = {}
function! ghpr_blame#slug#from_url(url) abort
    let slug = deepcopy(s:SLUG)
    let m = matchlist(a:url, '\v^git\@([^:]+):([^/]+/[^/]{-})%(\.git)?\n*$')
    if empty(m)
        let m = matchlist(a:url, '\v^%(git|https|ssh)://%([^@/]+\@)?([^/]+)/([^/]+/[^/]{-})%(\.git)?\n*$')
    endif
    if empty(m)
        throw 'Cannot detect a remote URL'
    endif
    let slug.host = m[1]
    let slug.path = m[2]
    return slug
endfunction

function! s:_auth_token() dict abort
    let raw = get(g:, 'ghpr_github_auth_token', {})
    let token = {}
    if type(raw) == type('')
        let token['github.com'] = raw
    elseif type(raw) == type({})
        let token = raw
    endif
    return get(token, self.host, '')
endfunction
let s:SLUG.auth_token = function('s:_auth_token')

function! s:_api_url(num) dict abort
    if self.host ==# 'github.com'
        let url = 'api.github.com'
    else
        let api_url = get(g:, 'ghpr_github_api_url', {})
        let url = get(api_url, self.host, '')
        if url ==# ''
            return ''
        endif
    endif
    return printf('%s/repos/%s/pulls/%d', url, self.path, a:num)
endfunction
let s:SLUG.api_url = function('s:_api_url')

function! s:_fetch_pr(num) dict abort
    let headers = {'Accept': 'application/vnd.github.v3+json'}
    let t = self.auth_token()
    if t !=# ''
        let headers.Authorization = 'token ' . t
    endif
    let url = self.api_url(a:num)
    if url ==# ''
        throw printf('unknown API url for %s', self.host)
    endif
    let response = s:H.request({
                \ 'url': url,
                \ 'headers': headers,
                \ 'method': 'GET',
                \ 'client': ['curl', 'wget'],
                \ })
    if !response.success
        throw printf('API request failed with status %s: %s', response.status, response)
    endif
    return json_decode(response.content)
endfunction
let s:SLUG.fetch_pr = function('s:_fetch_pr')
