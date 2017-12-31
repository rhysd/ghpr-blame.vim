if (exists('g:loaded_ghpr_blame') && g:loaded_ghpr_blame) || &cp
    finish
endif

command! -nargs=* -bar GHPRBlame call ghpr_blame#start()
command! -nargs=0 -bar GHPRBlameQuit call ghpr_blame#quit()

let g:loaded_ghpr_blame = 1
