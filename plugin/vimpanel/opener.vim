let s:Opener = {}
let g:VimpanelOpener = s:Opener

" constructor
" path: the path object that is to be opened.
" opts: a dictionary containing the following keys (all optional):
"  'where': Specifies whether the node should be opened in new split/tab or in
"           the previous window. Can be either 'v' or 'h' or 't' (for open in new tab)
"  'reuse': if a window is displaying the file then jump the cursor there
"  'keepopen': dont close the tree window
"  'stay': open the file, but keep the cursor in the tree win
function! s:Opener.New(path, opts)
  let newObj = copy(self)

  let newObj._path = a:path
  let newObj._stay = vimpanel#has_opt(a:opts, 'stay')
  let newObj._reuse = vimpanel#has_opt(a:opts, 'reuse')
  let newObj._keepopen = vimpanel#has_opt(a:opts, 'keepopen')
  let newObj._where = has_key(a:opts, 'where') ? a:opts['where'] : ''
  call newObj._saveCursorPos()

  return newObj
endfunction

function! s:Opener._gotoTargetWin()
  if self._where == 'v'
    call self._newVSplit()
  elseif self._where == 'h'
    call self._newSplit()
  elseif self._where == 't'
    tabnew
  elseif self._where == 'p'
    call self._previousWindow()
  endif
endfunction

function! s:Opener._newSplit()
    " Save the user's settings for splitbelow and splitright
    let savesplitbelow=&splitbelow
    let savesplitright=&splitright

    " 'there' will be set to a command to move from the split window
    " back to the explorer window
    "
    " 'back' will be set to a command to move from the explorer window
    " back to the newly split window
    "
    " 'right' and 'below' will be set to the settings needed for
    " splitbelow and splitright IF the explorer is the only window.
    "
    let there = "wincmd h"
    let back = "wincmd l"
    let right = 1
    let below = 0

    " Attempt to go to adjacent window
    call vimpanel#exec(back)

    let onlyOneWin = (winnr("$") ==# 1)

    " If no adjacent window, set splitright and splitbelow appropriately
    if onlyOneWin
        let &splitright=right
        let &splitbelow=below
    else
        " found adjacent window - invert split direction
        let &splitright=!right
        let &splitbelow=!below
    endif

    let splitMode = onlyOneWin ? "vertical" : ""

    " Open the new window
    try
        exec(splitMode." sp ")
    catch /^Vim\%((\a\+)\)\=:E37/
        call s:putCursorInTreeWin()
        throw "Vimpanel.FileAlreadyOpenAndModifiedError: ". self._path.str() ." is already open and modified."
    catch /^Vim\%((\a\+)\)\=:/
        "do nothing
    endtry

    "resize the tree window if no other window was open before
    if onlyOneWin
        let size = g:VimpanelWinSize
        call vimpanel#exec(there)
        exec("silent ". splitMode ." resize ". size)
        call vimpanel#exec('wincmd p')
    endif

    " Restore splitmode settings
    let &splitbelow=savesplitbelow
    let &splitright=savesplitright
endfunction

function! s:Opener._newVSplit()
  let winwidth = winwidth(".")
  if winnr("$")==#1
    let winwidth = g:VimpanelWinSize
  endif

  call vimpanel#exec("wincmd p")
  vnew

  "resize the vimpanel back to the original size
  call s:putCursorInTreeWin()
  exec("silent vertical resize ". winwidth)
  call vimpanel#exec('wincmd p')
endfunction

function! s:Opener.open(target)
  if self._path.isDirectory
    return
  else
    call self._openFile()
  endif
endfunction

function! s:Opener._openFile()
  if self._reuse && self._reuseWindow()
    return
  endif

  call self._gotoTargetWin()

  call self._path.edit()

  if self._stay
    call self._restoreCursorPos()
  endif
endfunction

function! s:Opener._previousWindow()
  if !vimpanel#isWindowUsable(winnr("#")) && vimpanel#firstUsableWindow() ==# -1
    call self._newSplit()
  else
    try
      if !vimpanel#isWindowUsable(winnr("#"))
        call vimpanel#exec(vimpanel#firstUsableWindow() . "wincmd w")
      else
        call vimpanel#exec('wincmd p')
      endif
    catch /^Vim\%((\a\+)\)\=:E37/
      call s:putCursorInTreeWin()
      throw "Vimpanel.FileAlreadyOpenAndModifiedError: ". self._path.str() ." is already open and modified."
    catch /^Vim\%((\a\+)\)\=:/
      echo v:exception
    endtry
  endif
endfunction

function! s:Opener._restoreCursorPos()
  call vimpanel#exec('normal ' . self._tabnr . 'gt')
  call vimpanel#exec(bufwinnr(self._bufnr) . 'wincmd w')
endfunction

" puts the cursor in the first window we find for this file
" returns 1 if successful
function! s:Opener._reuseWindow()
  "check the current tab for the window
  let winnr = bufwinnr('^' . self._path.str() . '$')
  if winnr != -1
    call vimpanel#exec(winnr . "wincmd w")
    return 1
  endif
  return 0
endfunction

function! s:Opener._saveCursorPos()
  let self._bufnr = bufnr("")
  let self._tabnr = tabpagenr()
endfunction
