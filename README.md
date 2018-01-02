Blaming Pull Requests in the file on Vim
========================================

[ghpr-blame.vim][] is a Vim plugin to investigate which line is modified by which pull request.
It's like `git-blame`, but `git-blame` shows which line is modified by which commit.

![screenshot](https://github.com/rhysd/ss/raw/master/ghpr-blame.vim/main.jpg)

This Vim plugin was inspired by [@kazuho's tiny script](https://gist.github.com/kazuho/eab551e5527cb465847d6b0796d64a39).

## Usage

### 1. Run `:GHPRBlame` in the file

By running `:GHPRBlame`, it extract necessary information from `git-blame` command and creates a
list in a temporary window at left of current window.
The temporary window is automatically scrolled when you scroll the current window (see `:help scrollbind`
for the detail).

You can know which line is modified by which pull request by seeing the list.

### 2. Type enter key to know the detail of the pull request

When `:GHPRBlame`, it automatically defines a buffer local mapping for inspecting the pull request
for the current line. If you want to know the detail of the current line, please type `<CR>` (it can
be customized by `g:ghpr_show_pr_mapping`). It creates another temporary window and show the detail
of the pull request in it.

### 3. Close the list window or run `:GHPRBlameQuit` for cleanup

After your work has been done, please close the list window for pull requests or run `:GHPRBlameQuit`
explicitly. It cleans up the cache for fetching pull requests and `git-blame`.

## Setup API Token

To fetch the information of pull request, this plugin uses [GitHub PullRequest API][]. It may hit
API rate limit when using this plugin heavily.

1. Visit https://github.com/settings/tokens in a browser
2. Click 'Generate new token'
3. Add token description
4. Without checking any checkbox, click 'Generate token'
5. Generated token is shown at the top of your tokens list
6. Set it to `g:ghpr_github_auth_token` (Please be careful. The token is a credential)

[ghpr-blame.vim]: https://bithub.com/rhysd/ghpr-blame.vim
[GitHub PullRequest API]: https://developer.github.com/v3/pulls/
