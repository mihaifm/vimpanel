let vimpanel#version = '1.0.3'

if exists("g:loaded_vimpanel_autoload")
  finish
endif
let g:loaded_vimpanel_autoload = 1

""""""""""
" Globals

" storage file name
let vimpanel#storage_file = ''
" session file name
let vimpanel#session_file = ''

" session management lists
let vimpanel#state_output_list = []
let vimpanel#state_input_list = []

""""""""""""""""""""""""""""
" General utility functions

function! vimpanel#has_opt(options, name)
  return has_key(a:options, a:name) && a:options[a:name] == 1
endfunction

" same as :exec cmd  but eventignore=all is set for the duration
function! vimpanel#exec(cmd)
  let old_ei = &ei
  set ei=all
  exec a:cmd
  let &ei = old_ei
endfunction

function! vimpanel#OS_Windows()
  return has("win32") || has("win64")
endfunction

function! vimpanel#echo(msg)
  redraw
  echomsg "Vimpanel: " . a:msg
endfunction

function! vimpanel#echoWarning(msg)
  echohl warningmsg
  call vimpanel#echo(a:msg)
  echohl normal
endfunction

function! vimpanel#echoError(msg)
  echohl errormsg
  call vimpanel#echo(a:msg)
  echohl normal
endfunction

function vimpanel#blank(str)
  if match(a:str, '^\s*$') == -1
    return 0
  endif
  return 1
endfunction

" returns a list without duplicates
function! vimpanel#unique(list)
  let uniqlist = []
  for elem in a:list
    if index(uniqlist, elem) ==# -1
      call add(uniqlist, elem)
    endif
  endfor
  return uniqlist
endfunction

"""""""""""""""""""""""""""""""
" Buffer and window management

" determine the number of windows open to this buffer number.
function! vimpanel#bufInWindows(bnum)
  let cnt = 0
  let winnum = 1
  while 1
    let bufnum = winbufnr(winnum)
    if bufnum < 0
      break
    endif
    if bufnum ==# a:bnum
      let cnt = cnt + 1
    endif
    let winnum = winnum + 1
  endwhile

  return cnt
endfunction

" finds the window number of the first normal window
function! vimpanel#firstUsableWindow()
  let i = 1
  while i <= winnr("$")
    let bnum = winbufnr(i)
    if bnum != -1 && getbufvar(bnum, '&buftype') ==# ''
          \ && !getwinvar(i, '&previewwindow')
          \ && (!getbufvar(bnum, '&modified') || &hidden)
      return i
    endif

    let i += 1
  endwhile
  return -1
endfunction

" gets the panel names from the :ls output
function! vimpanel#listAllPanels()
  let retlist = []

  redir => lsoutput 
  exe "silent ls!"
  redir END

  let lines = split(lsoutput, '\n') 
  for line in lines
    let bits = split(line, '"')
    let bufno = str2nr(bits[0])
    let path = bits[1]

    if path =~? "^vimpanel-"
      let panel_name = substitute(path, "^vimpanel-", '', '')
      call add(retlist, panel_name)
    endif
  endfor

  return retlist
endfunction

" if a panel is loaded in the current window, returns it's name
" otherwise returns a blank string
function! vimpanel#panelFromWindow()
  let name = bufname(winbufnr(0))
  if name =~? "^vimpanel-"
    return substitute(name, "^vimpanel-", '', '') 
  else
    return ''
  endif
endfunction

" replaces the buffer with the given bufnum with a new one
function! vimpanel#replaceAfterRename(bufnum, newFileName)
  " ensure that a new buffer is loaded
  exec "badd " . a:newFileName
  " ensure that all windows which display the just deleted filename
  " display a buffer for a new filename
  let originalTabNumber = tabpagenr()
  let originalWindowNumber = winnr()
  exec "tabdo windo if winbufnr(0) == " . a:bufnum . " | exec ':e! " . a:newFileName . "' | endif"
  exec "tabnext " . originalTabNumber
  exec originalWindowNumber . "wincmd w"
  " we don't need a previous buffer anymore
  exec "bwipeout! " . a:bufnum
endfunction

"""""""""""""""""""
" Helper functions

" indent level for each node
function! vimpanel#indent()
  return 2
endfunction

" number of files that trigger a notification when refreshing/reading a node
function! vimpanel#notifThreshold()
  return 100
endfunction

" chars passed in to the escape calls 
function! vimpanel#escapeChars()
  if vimpanel#OS_Windows()
    return  " `\|\"#%&,?()\*^<>"
  endif
  return " \\`\|\"#%&,?()\*^<>[]"
endfunction

" moves the tree up a level
" keepState: 1 if the current root should be left open when the tree is re-rendered
function! vimpanel#upDir(keepState)
  if !b:explorer_mode
    return
  endif
 
  let root_data = vimpanel#rootDataFromLine(1)
  let cwd = root_data.root.path.str({'format': 'UI'})
  if cwd ==# "/" || cwd =~# '^[^/]..$'
    call vimpanel#echo("already at top dir")
  else
    if !a:keepState
      call root_data.root.close()
    endif

    let oldRoot = root_data.root

    if empty(root_data.root.parent)
      let path = root_data.root.path.getParent()
      let newRoot = g:VimpanelTreeDirNode.New(path)
      call newRoot.open()
      call newRoot.transplantChild(root_data.root)

      let b:tree_objects = [newRoot]
    else
      let b:tree_objects = [root_data.root.parent]
    endif

    call vimpanel#renderPanel()
    " todo - check if this works 
    " call oldRoot.putCursorHere(0, 0)
  endif
endfunction

" gets the full path to the node that is rendered on the given line number
" ln: the line number to get the path for
" root: the root object
" rootLine: line where the root resides
" returns: a path if a node was selected, {} if nothing is selected.
function! vimpanel#getPath(ln, root, rootLine)
  let line = getline(a:ln)

  let rootLine = a:rootLine
  let root = a:root

  " check to see if we have the root node
  if a:ln == rootLine
    return root.path
  endif

  if !g:VimpanelDirArrows
    " in case called from outside the tree
    if line !~# '^ *[|`▸▾ ]' || line =~# '^$'
      return {}
    endif
  endif

  let indent = vimpanel#indentLevelFor(line)

  " remove the tree parts and the leading space
  let curFile = vimpanel#stripMarkupFromLine(line, 0)

  let dir = ""
  let lnum = a:ln
  while lnum > 0
    let lnum = lnum - 1
    let curLine = getline(lnum)
    let isDir = 0
    if curLine =~# '\v(\|\+)|(`\+)|(\|\~)|(`\~)' 
      let isDir = 1
    endif
    let curLineStripped = vimpanel#stripMarkupFromLine(curLine, 1)

    "have we reached the top of the tree?
    if lnum == rootLine
      let dir = root.path.str({'format': 'UI'}) . dir
      break
    endif
    if isDir
      let lpindent = vimpanel#indentLevelFor(curLine)
      if lpindent < indent
        let indent = indent - 1

        let dir = substitute (curLineStripped,'^\\', "", "") . dir
        continue
      endif
    endif
  endwhile
  let curFile = root.path.drive . dir . curFile
  let toReturn = g:VimpanelPath.New(curFile)
  return toReturn
endfunction

" calculates indent
function! vimpanel#indentLevelFor(line)
  if a:line !~# vimpanel#nonRootExpr()
    return 0
  endif

  let level = match(a:line, '[^ \-+~▸▾`|]') / vimpanel#indent() 
  " check if line includes arrows
  if match(a:line, '[▸▾]') > -1
    " decrement level as arrow uses 3 ascii chars
    let level = level - 1
  endif
  return level
endfunction

" returns 0 if opening a file from the tree in the given window requires it to be split, 1 otherwise
function! vimpanel#isWindowUsable(winnumber)
  " gotta split if theres only one window (i.e. the vimpanel)
  if winnr("$") ==# 1
    return 0
  endif

  let oldwinnr = winnr()
  call vimpanel#exec(a:winnumber . "wincmd p")
  let specialWindow = getbufvar("%", '&buftype') != '' || getwinvar('%', '&previewwindow')
  let modified = &modified
  call vimpanel#exec(oldwinnr . "wincmd p")

  " if it's a special window e.g. quickfix or another explorer plugin then we have to split
  if specialWindow
    return 0
  endif

  if &hidden
    return 1
  endif

  return !modified || vimpanel#bufInWindows(winbufnr(a:winnumber)) >= 2
endfunction

" returns the given line with all the tree parts stripped off
" line: the subject line
" removeLeadingSpaces: 1 if leading spaces are to be removed 
" (leading spaces = any spaces before the actual text of the node)
function! vimpanel#stripMarkupFromLine(line, removeLeadingSpaces)
  let line = a:line
  "remove the tree parts and the leading space
  let line = substitute (line, '^[ `|]*[\-+~]',"" ,"")

  "strip off any read only flag
  let line = substitute (line, ' \[RO\]', "","")

  "strip off any executable flags
  let line = substitute (line, '*\ze\($\| \)', "","")

  let wasdir = 0
  if line =~# '/$'
    let wasdir = 1
  endif
  let line = substitute (line,' -> .*',"","") " remove link to
  if wasdir ==# 1
    let line = substitute (line, '/\?$', '/', "")
  endif

  if a:removeLeadingSpaces
    let line = substitute (line, '^ *', '', '')
  endif

  return line
endfunction

" changes vim's cwd to the path of the given node
function! vimpanel#chCwd(node)
  try
    call a:node.path.changeToDir()
  catch /^Vimpanel.PathChangeError/
    call vimpanel#echoWarning("could not change cwd")
  endtry
endfunction

" changes the current root to the selected one
function! vimpanel#chRoot()
  if !b:explorer_mode
    return
  endif

  let curNode = vimpanel#getSelectedNode()
  if empty(curNode) || !curNode.path.isDirectory  
    return
  endif

  call curNode.makeRoot()
  call vimpanel#renderPanel()
endfunction

" closes all childnodes of the current node
function! vimpanel#closeChildren(node)
  call a:node.closeChildren()
  call vimpanel#renderPanel()
  call a:node.putCursorHere(0, 0)
endfunction

" sets properties for the panel buffer and initializes buffer variables
function! vimpanel#setPanelBufProperties(panel_name)
  setlocal nonumber
  setlocal foldcolumn=0
  setlocal nofoldenable
  setlocal cursorline
  setlocal nospell
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nowrap
  setfiletype vimpanel
  setlocal winfixwidth
        
  let &l:statusline = " " . a:panel_name

  let b:roots = copy(g:VimpanelRoots)
  let b:session_file = g:vimpanel#session_file
  let b:storage_file = g:vimpanel#storage_file

  if !exists("b:tree_objects")
    let b:tree_objects = []
  endif

  if !exists("b:copied_nodes")
    let b:copied_nodes = []
  endif

  let b:explorer_mode = 0

  call VimpanelBindMappings()
endfunction

" renders the current panel
function! vimpanel#renderPanel()
  setlocal modifiable

  let curLine = line(".")
  let curCol = col(".")
  let topLine = line("w0")

  "delete all lines in the buffer (being careful not to clobber a register)
  silent 1,$delete _

  for root in b:tree_objects
    call s:renderSingleRoot(root)
  endfor

  "delete the blank line at the top of the buffer
  silent 1,1delete _

  "restore the view
  let old_scrolloff=&scrolloff
  let &scrolloff=0
  call cursor(topLine, 1)
  normal! zt
  call cursor(curLine, curCol)
  let &scrolloff = old_scrolloff

  setlocal nomodifiable
endfunction

" renders a root object
function! s:renderSingleRoot(root_obj)
  "draw the header line
  let header = a:root_obj.path.str({'format': 'Root', 'truncateTo': winwidth(0)})
  call setline(line(".") + 1, header)
  call cursor(line(".") + 1, col("."))

  "draw the tree
  let old_o = @o
  let @o = a:root_obj.renderToString()
  exe 'normal "ogp'
  let @o = old_o
endfunction

" returns a regex representing the allowed format for non-root lines
function! vimpanel#nonRootExpr()
  return '\v^\s*[`|]'
endfunction

" gets the root of the selected node
" args:
"   lineno - line number to start searching
" returns a Dict with 2 keys:
"   .root - the root object
"   .root_line - the root line
function! vimpanel#rootDataFromLine(lineno)
  let line = getline(a:lineno)

  if vimpanel#blank(line)
    return {}
  endif

  " the only accurate way is to count the lines up to the top 
  let roots_found = 0
  let root_lines = []
  let lidx = a:lineno
  while lidx > 0 
    let linestr = getline(lidx)
    if !vimpanel#blank(linestr) && linestr !~# vimpanel#nonRootExpr()
      let roots_found += 1
      call insert(root_lines, lidx)
    endif
    let lidx -= 1
  endwhile

  let retval = {}
  if roots_found > 0
    let retval.root = b:tree_objects[roots_found-1]
    let retval.root_line = root_lines[roots_found-1]
    return retval
  else
    call vimpanel#echo("some kind of weird error")
    return {}
  endif
endfunction

" read storage and session files
function! vimpanel#readPanelData(panel_name)
  if !isdirectory(g:VimpanelStorage)
    call vimpanel#echo("invalid vimpanel storage")
    return
  endif

  let g:vimpanel#storage_file = g:VimpanelStorage . '/' . a:panel_name
  if !filereadable(g:vimpanel#storage_file)
    call vimpanel#echo(a:panel_name . " not found")
    return
  endif

  let g:VimpanelRoots = readfile(g:vimpanel#storage_file)
  " ignore blank lines
  let g:VimpanelRoots = filter(g:VimpanelRoots, "!vimpanel#blank(v:val)")

  let g:vimpanel#session_file = g:vimpanel#storage_file . "_session"

  if !filereadable(g:vimpanel#session_file)
    call writefile([], g:vimpanel#session_file)
  else
    let g:vimpanel#state_input_list = readfile(g:vimpanel#session_file)
    let g:vimpanel#state_input_list = map(g:vimpanel#state_input_list, "tolower(v:val)")
  endif
endfunction

" captures directory edits
function! vimpanel#captureDir(dir)
  if a:dir != '' && isdirectory(a:dir)
    call Vimpanel(a:dir)
    exe "bw " . a:dir
  endif
endfunction

" converts the paths to Path objects
" args: 
"   paths: array of paths to be converted
"   insert_invalid: if 1, insert an empty object for invalid paths
" returns: an array of Path objects
function! vimpanel#pathsToOjects(paths, insert_invalid)
  let retlist = []

  for root in a:paths
    let path = {}
    let dir = g:VimpanelPath.Resolve(root)

    try
      let path = g:VimpanelPath.New(dir)
    catch /^Vimpanel.InvalidArgumentsError/
      call vimpanel#echo("no file or directory found for: " . dir)
      if a:insert_invalid
        let path = {}
      else
        continue
      endif
    endtry

    call add(retlist, path)
  endfor

  return retlist
endfunction

" syncs g:VimpanelRoots with b:tree_objects
function! vimpanel#syncObjects()
  let output_tree_objects = []

  let root_paths = vimpanel#pathsToOjects(b:roots, 0)

  for root_path in root_paths
    let obj = s:rootInTreeObjects(root_path)
    if !empty(obj)
      call add(output_tree_objects, obj)
    else
      if root_path.isDirectory
        let newRoot = g:VimpanelTreeDirNode.New(root_path)
        call add(output_tree_objects, newRoot)
      else
        let newRoot = g:VimpanelTreeFileNode.New(root_path)
        call add(output_tree_objects, newRoot)
      endif
    endif
  endfor

  let b:tree_objects = output_tree_objects
endfunction

" searches for a root path in the tree objects
function! s:rootInTreeObjects(root_path_obj)
  for tree_object in b:tree_objects
    if tree_object.path.str() ==? a:root_path_obj.str()
      return tree_object
    endif
  endfor
  return {}
endfunction

" gets the node under cursor
function! vimpanel#getSelectedNode()
  let root_data = vimpanel#rootDataFromLine(line("."))
  if root_data ==# {}
    return {}
  endif

  let path = vimpanel#getPath(line("."), root_data.root, root_data.root_line)
  let node = root_data.root.findNode(path)

  return node
endfunction

" gets node from line, of course
function! vimpanel#getNodeFromLine(line)
  let root_data = vimpanel#rootDataFromLine(a:line)
  if root_data ==# {}
    return {}
  endif
  let path = vimpanel#getPath(a:line, root_data.root, root_data.root_line)
  let node = root_data.root.findNode(path)
  return node
endfunction

" opens the node under cursor
function! vimpanel#selectNode()
  let node = vimpanel#getSelectedNode()

  if node ==# {}
    return
  endif

  if node.path.isDirectory
    call node.activate({'reuse': 1})
  else
    call node.activate({'reuse': 1, 'where': 'p'})
  endif
endfunction

" opens the node in a new tab
function! vimpanel#tabNode()
  let node = vimpanel#getSelectedNode()

  if node ==# {}
    return
  endif

  if !node.path.isDirectory
    call node.activate({'reuse': 1, 'where': 't'})
  endif
endfunction

" refreshes the node under cursor
function! vimpanel#refreshNode()
  let node = vimpanel#getSelectedNode()
  if node ==# {}
    return
  endif

  if node.path.isDirectory
    call node.refresh()
  endif
  
  call vimpanel#renderPanel()
endfunction

" init storage location
" returns 1 for success, 0 for failure
function! vimpanel#initStorageDir()
  if !isdirectory(g:VimpanelStorage)
    call mkdir(g:VimpanelStorage)
    if !isdirectory(g:VimpanelStorage)
      call vimpanel#echo("cannot create vimpanel storage")
      return 0
    endif
  endif
  return 1
endfunction

" hides the special markup characters using the highlight scheme background
" this is better than using the Ignore group
function! vimpanel#hideMarkup()
  redir => group_details
  exe "silent hi Normal"
  redir END

  " resolve linked groups to find the root highlighting scheme
  while group_details =~ "links to"
    let index = stridx(group_details, "links to") + len("links to")
    let linked_group =  strpart(linked_group, index + 1)
    redir => linked_group
    exe "silent hi " . linked_group
    redir END
  endwhile

  " extract the highlighting details (the bit after "xxx")
  let match_groups = matchlist(group_details, '\<xxx\>\s\+\(.*\)')
  let existing_highlight = match_groups[1]

  " check whether there's an existing guibg= block
  let match_groups = matchlist(existing_highlight, '\vguibg\=\s*(\S+)')
  if match_groups != []
    let bg_color = match_groups[1]

    exe "hi VimpanelPart guifg=" . bg_color . " guibg=" . bg_color
    exe "hi VimpanelOpenable guifg=" . bg_color . " guibg=" . bg_color
    exe "hi VimpanelClosable guifg=" . bg_color . " guibg=" . bg_color
    exe "hi VimpanelPartFile guifg=" . bg_color . " guibg=" . bg_color
    exe "hi VimpanelEndSlash guifg=" . bg_color . " guibg=" . bg_color
  endif
endfunction
