if exists("loaded_vimpanel")
  finish
endif
let loaded_vimpanel = 1

function! s:initVariable(var, value)
  if !exists(a:var)
    exec 'let ' . a:var . ' = ' . "'" . substitute(a:value, "'", "''", "g") . "'"
    return 1
  endif
  return 0
endfunction

if vimpanel#OS_Windows()
  call s:initVariable("g:VimpanelRemoveDirCmd", 'rmdir /s /q')
  call s:initVariable("g:VimpanelCopyDirCmd", 'xcopy /s /e /i /y /q ')
  call s:initVariable("g:VimpanelCopyFileCmd", 'copy /y ')
else
  call s:initVariable("g:VimpanelRemoveDirCmd", 'rm -rf')
  call s:initVariable("g:VimpanelCopyDirCmd", 'cp -r')
  call s:initVariable("g:VimpanelCopyFileCmd", 'cp -r')
endif

call s:initVariable("g:VimpanelStorage", '~/vimpanel')
call s:initVariable("g:VimpanelDirArrows", 0)
call s:initVariable("g:VimpanelCompact", 0)
call s:initVariable("g:VimpanelWinSize", 31)
call s:initVariable("g:VimpanelShowHidden", 1)

" load modules
runtime plugin/vimpanel/path.vim
runtime plugin/vimpanel/tree_file_node.vim
runtime plugin/vimpanel/tree_dir_node.vim
runtime plugin/vimpanel/opener.vim

" script variables
let s:active_panel_bufnr = -1
let s:active_panel_bufname = ''
let s:active_panel = ''

" this holds the roots of the last opened buffer
let g:VimpanelRoots = []

" buffer variables

" b:roots contains the paths of the root nodes
" this should always be in sync with the panel storage file
let b:roots = []

" contains the actual tree objects displayed on the screen
let b:tree_objects = []

" expand the storage folder
let g:VimpanelStorage = expand(g:VimpanelStorage)

" autocomplete for panel names
function! s:CompletePanelNames(A, L, P)
  if !isdirectory(g:VimpanelStorage)
    return
  endif

  let retlist = []
  let files = split(globpath(g:VimpanelStorage, '*', 1), '\n')

  for filename in files
    let pathbits = split(filename, '\v\\|/', 1)
    let shortname = pathbits[len(pathbits)-1]
    if shortname =~? '_session$' || shortname =~? '\.vim$'
      continue
    endif
    call add(retlist, shortname)
  endfor

  return filter(retlist, 'v:val =~# "^' . a:A . '"')
endfunction

function! s:CompleteSessionNames(A, L, P)
  if !isdirectory(g:VimpanelStorage)
    return
  endif

  let retlist = []
  let files = split(globpath(g:VimpanelStorage, '*.vim', 1), '\n')

  for filename in files
    let pathbits = split(filename, '\v\\|/', 1)
    let shortname = pathbits[len(pathbits)-1]
    let shortname = substitute(shortname, '\.vim', '', '')
    call add(retlist, shortname)
  endfor

  return filter(retlist, 'v:val =~# "^' . a:A . '"')
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelCreate - create the files used by the panel

function! VimpanelCreate(name)
  if !vimpanel#initStorageDir()
    return
  endif

  let vimpanel#storage_file = g:VimpanelStorage . '/' . a:name
  if filereadable(vimpanel#storage_file)
    call vimpanel#echo(a:name . " already exists. Please specify another name")
    return
  endif

  let s:active_panel = a:name
  let s:active_panel_bufname = "vimpanel-" . a:name
  let g:VimpanelRoots = []

  let vimpanel#session_file = vimpanel#storage_file . "_session"

  call writefile([], vimpanel#storage_file)
  call writefile([], vimpanel#session_file)
  call vimpanel#echo("done")
endfunction

"""""""""""""""""""""""""""""""""""""""""""""
" VimpanelAdd - adds an entity (file or dir)
" to the storage file

function! VimpanelAdd(entity_name)
  if a:entity_name == ''
    return
  endif

  if s:active_panel_bufnr < 0
    call vimpanel#echo("no panel found")
    return
  endif

  let roots = []
  let storage_file = ''

  if vimpanel#blank(vimpanel#panelFromWindow())
    let vp_winnr = bufwinnr(s:active_panel_bufnr)
    if vp_winnr == -1
      let roots = g:VimpanelRoots
      let storage_file = vimpanel#storage_file
    else
      exe vp_winnr . "wincmd w"
      let roots = b:roots
      let storage_file = b:storage_file
    endif
  else
    let roots = b:roots
    let storage_file = b:storage_file
  endif

  let entry_object = vimpanel#pathsToOjects([a:entity_name], 0)
  if empty(entry_object) 
    return
  endif

  let path_objects = vimpanel#pathsToOjects(roots, 0)

  " check for duplication
  for path_obj in path_objects
    if path_obj.str() ==? entry_object[0].str()
      call vimpanel#echo("already contains " . a:entity_name)
      return
    endif
  endfor

  " check for existance
  if !isdirectory(a:entity_name) && !filereadable(a:entity_name)
    call vimpanel#echo(a:entity_name . " does not exist") 
    return
  endif

  call add(roots, a:entity_name)

  call writefile(roots, storage_file)
endfunction


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelRemove - removes the selected root from the storage file

function! VimpanelRemove() 
  let curNode = vimpanel#getSelectedNode()
  " only root nodes allowed
  if curNode ==# {} || !curNode.isRoot()
    return 
  endif

  let path_objects = vimpanel#pathsToOjects(b:roots, 1)

  let idx = 0
  for path_obj in path_objects
    if empty(path_obj)
      let idx += 1
      continue
    endif
    if curNode.path.str() ==? path_obj.str() 
      call remove(b:roots, idx)
      break
    endif
    let idx += 1
  endfor

  call writefile(b:roots, b:storage_file)

  call VimpanelRebuild()
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""
" Vimpanel - adds an entity and refreshes the panel

function! Vimpanel(entity_name)
  call VimpanelAdd(a:entity_name)
  call VimpanelRebuild()
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelOpen - put a panel on the screen
" use_session: use the session file to expand nodes

function! VimpanelOpen(panel_name, use_session)
  if vimpanel#blank(a:panel_name)
    return
  endif

  call vimpanel#readPanelData(a:panel_name)

  if s:active_panel_bufnr < 0
    if len(s:active_panel_bufname) == 0
      let s:active_panel_bufname = "vimpanel-" . a:panel_name 
    endif

    exe "e " . s:active_panel_bufname
  else
    if s:active_panel == a:panel_name
      " check if this buffer still exists
      if !bufexists(s:active_panel_bufname)
        exe "e " . s:active_panel_bufname
      else
        " check if vimpanel is active in a window
        let vp_winnr = bufwinnr(s:active_panel_bufname)
        if vp_winnr == -1
          exe "b " . s:active_panel_bufnr
        else
          exe vp_winnr . "wincmd w"
        endif
      endif
    else
      let s:active_panel_bufname = "vimpanel-" . a:panel_name 
      exe "e " . s:active_panel_bufname
    endif
  endif

  let s:active_panel_bufnr = bufnr(s:active_panel_bufname)
  let s:active_panel = a:panel_name

  call vimpanel#setPanelBufProperties(s:active_panel)

  call vimpanel#syncObjects()

  if a:use_session
    for tree in b:tree_objects
      call tree.restoreState()
    endfor
  endif

  call vimpanel#renderPanel()
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelRebuild - rebuilds the panel by  loading from the storage file
" needed after adding/removing roots

function! VimpanelRebuild()
  let panel_name = vimpanel#panelFromWindow()
  if !vimpanel#blank(panel_name)
    call VimpanelOpen(panel_name, 0)
  else
    call VimpanelOpen(s:active_panel, 0)
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelSave - save the panel session (open nodes)

function! VimpanelSave()
  if b:explorer_mode
    call vimpanel#echoWarning("cannot save state in explorer mode")
    return
  endif
  let g:vimpanel#state_output_list = []
  for tree in b:tree_objects
    call tree.saveState()
  endfor
  call writefile(g:vimpanel#state_output_list, b:session_file)
  call vimpanel#echo("done")
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelLoad - load all nodes from the storage
" expand nodes according to the session file

function! VimpanelLoad(panel_name)
  call VimpanelOpen(a:panel_name, 1)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelRefresh -rebuilds the panel by reading entries from the storage file
" refreshes all roots from the filesystem

function! VimpanelRefresh()
  if vimpanel#blank(vimpanel#panelFromWindow())
    return
  else
  " todo - switch to the active panel
  endif

  if !b:explorer_mode
    call VimpanelRebuild()
  endif

  for root_obj in b:tree_objects
    call vimpanel#echo("refreshing " . root_obj.path.str())
    call root_obj.refresh()
  endfor
  call vimpanel#renderPanel()
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelPathToClipboard - copy the node path into clipboard

function! VimpanelPathToClipboard()
  let curNode = vimpanel#getSelectedNode()
  if empty(curNode)
    return
  endif

  let path = curNode.path.str()
  let @+ = path
  echo path 
endfunction

"""""""""""""""""""""""""""""""""""
" VimpanelMoveNode - rename a node

function! VimpanelMoveNode()
  let curNode = vimpanel#getSelectedNode()
  if curNode ==# {} || curNode.isRoot()
    return 
  endif

  let newNodePath = input("New path: ", curNode.path.str(), "file")

  if newNodePath ==# ''
    call vimpanel#echo("rename aborted")
    return
  endif

  try
    let bufnr = bufnr(curNode.path.str())

    call curNode.rename(newNodePath)
    call vimpanel#renderPanel()

    if bufnr != -1
      call vimpanel#replaceAfterRename(bufnr, newNodePath)
    endif

    redraw
  catch /^Vimpanel/
    call vimpanel#echoWarning("node not renamed")
  endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelDelNode - delete node from the filesystem

function! VimpanelDelNode()
  let curNode = vimpanel#getSelectedNode()
  if curNode ==# {} || curNode.isRoot()
    return 
  endif

  let confirmed = 0
  if curNode.path.isDirectory
    echo "Remove directory: " . curNode.path.str() . " (Yn) ? " 
    let choice = nr2char(getchar())
    let confirmed = choice ==# 'Y'
  else
    echo "Remove node: " . curNode.path.str() . " (yN) ? " 
    let choice = nr2char(getchar())
    let confirmed = choice ==# 'y'
  endif

  if confirmed
    try
      call curNode.delete()
      call vimpanel#renderPanel()

      let bufnum = bufnr(curNode.path.str())
      if buflisted(bufnum)
        " remove any buffer containing the file
        " ensure that all windows which display the just deleted filename
        " now display an empty buffer (so a layout is preserved).
        let originalTabNumber = tabpagenr()
        let originalWindowNumber = winnr()
        exe "tabdo windo if winbufnr(0) == " . bufnum . " | exec ':enew! ' | endif"
        exe "tabnext " . originalTabNumber
        exe originalWindowNumber . "wincmd w"
        exe "bwipeout! " . bufnum
      endif

    catch /^Vimpanel/
      call vimpanel#echoWarning("could not remove node")
    endtry
  else
    call vimpanel#echo("delete aborted")
  endif
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelNewNode - create a new node in the filesystem

function! VimpanelNewNode()
  let curNode = vimpanel#getSelectedNode()
  if curNode ==# {}
    return 
  endif

  let newNodeName = input("New entry: ", curNode.path.str() . g:VimpanelPath.Slash(), "file")

  if newNodeName ==# ''
    call vimpanel#echo("node creation aborted")
    return
  endif

  try
    let newPath = g:VimpanelPath.Create(newNodeName)
    let root_data = vimpanel#rootDataFromLine(line("."))
    let parentNode = root_data.root.findNode(newPath.getParent())

    let newTreeNode = g:VimpanelTreeFileNode.New(newPath)
    if parentNode.isOpen || !empty(parentNode.children)
      call parentNode.addChild(newTreeNode, 1)
      call vimpanel#renderPanel()
    endif
  catch /^Vimpanel/
    call vimpanel#echoWarning("node not created")
  endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelCopyNode - copy selected node into memory

function! VimpanelCopyNode()
  let b:copied_nodes = []
  let curNode = vimpanel#getNodeFromLine(line("."))
  if !empty(curNode)
    call add(b:copied_nodes, curNode)
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelCopyNodes - copy visually selected nodes into memory

function! VimpanelCopyNodes()
  let b:copied_nodes = []
  " start and end of the visual selection
  let startz = line("v")
  let endz = line(".")

  if startz > endz
    let tmp = startz
    let startz = endz
    let endz = tmp
  endif

  let i = startz
  while i <= endz
    let curNode = vimpanel#getNodeFromLine(i)
    if !empty(curNode)
      call add(b:copied_nodes, curNode)
    endif
    let i += 1
  endwhile

  " need to return something since this is called from an <expr> mapping
  return ""
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelPasteNodes - paste selected nodes under current directory
" if the current node is a file, they will be pasted under its parent

function! VimpanelPasteNodes()
  let curNode = vimpanel#getSelectedNode()
  if curNode ==# {}
    return 
  endif

  try
    let parent = {}
    if curNode.path.isDirectory
      let parent = curNode
    else
      let parent = curNode.getRoot().findNode(curNode.path.getParent())
    endif
    if !empty(parent)
      for copied_node in b:copied_nodes
        let new_fullpath = parent.path.str() . g:VimpanelPath.Slash()
        let new_fullpath .= copied_node.path.getLastPathComponent(0)
        call vimpanel#echo("copying " . copied_node.path.str() . " to " . new_fullpath)
        let newNode = copied_node.copy(new_fullpath)
        call parent.refresh()
      endfor

      call vimpanel#renderPanel()
    endif
  catch /^Vimpanel/
    call vimpanel#echoWarning("paste failed")
    let b:copied_nodes = []
  endtry
endfunction

""""""""""""""""""""""""""""""""""""""""""""
" VimpanelExploreMode - enter explorer mode

function! VimpanelExplorerMode()
  if b:explorer_mode
    " toggle it off
    let b:tree_objects = b:saved_tree_objects
    let b:saved_tree_objects = []
    let b:explorer_mode = 0
    let &l:statusline = " " . s:active_panel
    call vimpanel#renderPanel()
  else
    let curNode = vimpanel#getSelectedNode()
    if empty(curNode) || !curNode.path.isDirectory
      return
    endif

    let &l:statusline = " " . s:active_panel . " (explorer)"
    let b:explorer_mode = 1

    let b:saved_tree_objects = b:tree_objects
    let b:tree_objects = [curNode]

    call vimpanel#renderPanel()
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelSessionMake - save a global session with all 
" panels and open windows

function! VimpanelSessionMake(name)
  if !vimpanel#initStorageDir()
    return
  endif

  let panels = vimpanel#listAllPanels()

  for panel_name in panels
    " save only the visible ones
    let vp_winnr = bufwinnr("vimpanel-" . panel_name)
    if vp_winnr !=# -1
      exe vp_winnr . "wincmd w"
      call VimpanelSave()
    endif
  endfor

  let sess_file = ''
  if empty(a:name)
    let sess_file = g:VimpanelStorage ."/" . "default.vim"
  else
    let sess_file = g:VimpanelStorage ."/" . a:name . ".vim"
  endif

  set sessionoptions=buffers,tabpages,curdir,resize,winsize,blank,help,winpos
  exec "mksession! " . sess_file
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelSessionLoad - load the global vimpanel session
" which includes the panel and all open windows

function! VimpanelSessionLoad(name)
  set sessionoptions=buffers,tabpages,curdir,resize,winsize,blank,help,winpos

  if empty(a:name)
    let sess_file = g:VimpanelStorage . "/" . "default.vim"
  else
    let sess_file = g:VimpanelStorage . "/" . a:name . ".vim"
  endif

  if filereadable(sess_file)
    exec "silent source " . sess_file
  else
    call vimpanel#echoWarning("invalid session name")
    return
  endif

  let panels = vimpanel#listAllPanels()
  for panel_name in panels
    " check if vimpanel is active in a window
    let vp_winnr = bufwinnr("vimpanel-" . panel_name)

    if vp_winnr == -1
      "load it in the first window, then hide it
      exe "1wincmd w"
      let b = winbufnr(0)
      " exe "enew"
      call VimpanelLoad(panel_name)
      exe "b " . b
    else
      exe vp_winnr . "wincmd w"
      call VimpanelLoad(panel_name)
    endif
  endfor
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelEdit - edit the storage file associated with the panel

function! VimpanelEdit(panel_name)
  if !isdirectory(g:VimpanelStorage)
    call vimpanel#echo("invalid vimpanel storage")
    return
  endif

  let storage_file = g:VimpanelStorage . '/' . a:panel_name
  if !filereadable(storage_file)
    call vimpanel#echo(a:panel_name . " not found")
    return
  endif

  exe "e " . storage_file
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelToggle - toggle a panel in a location, topleft or botright

function! VimpanelToggle(panel_name, location)
  let active_panel_name = ''
  if empty(a:panel_name)
    let active_panel_name = s:active_panel
  else
    let active_panel_name = a:panel_name
  endif

  if empty(active_panel_name)
    call vimpanel#echoError("no panel name given")
    return
  endif

  let active_panel_bufname = "vimpanel-" . active_panel_name

  if bufexists(active_panel_bufname)
    let vp_winnr = bufwinnr(active_panel_bufname)
    if vp_winnr == -1
      exe a:location . " vertical " . g:VimpanelWinSize . " split"
      call VimpanelOpen(active_panel_name, 0)
    else
      exe vp_winnr . "wincmd w"
      exe "q"
    endif
  else
    exe a:location . " vertical " . g:VimpanelWinSize . " split"
    call VimpanelLoad(active_panel_name)
  endif
endfunction


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelViewHidden - toggle the display of files/folders starting with a .

function! VimpanelViewHidden()
  let g:VimpanelShowHidden = !g:VimpanelShowHidden
  call VimpanelRefresh()
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VimpanelBindMappings - mappings and commands for the vimpanel buffer

function! VimpanelBindMappings()
  " todo - make these keys configurable
  nnoremap <buffer> <silent> <CR>             :call vimpanel#selectNode()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse>    :call vimpanel#selectNode()<CR>
  nnoremap <buffer> <silent> o                :call vimpanel#selectNode()<CR>
  nnoremap <buffer> <silent> t                :call vimpanel#tabNode()<CR>
  nnoremap <buffer> <silent> <C-r>            :call vimpanel#refreshNode()<CR>

  nnoremap <buffer> <F5>                      :VimpanelRefresh<CR>
  nnoremap <buffer> <F6>                      :call VimpanelViewHidden()<CR>

  map <buffer> <silent> <C-c>                 :call VimpanelCopyNode()<CR>
  map <buffer> <silent> yy                    :call VimpanelCopyNode()<CR>

  xnoremap <expr> <buffer> <silent> <C-c>     VimpanelCopyNodes()
  snoremap <expr> <buffer> <silent> <C-c>     VimpanelCopyNodes()
  vnoremap <expr> <buffer> <silent> <C-c>     VimpanelCopyNodes()
  xnoremap <expr> <buffer> <silent> y         VimpanelCopyNodes()
  snoremap <expr> <buffer> <silent> y         VimpanelCopyNodes()
  vnoremap <expr> <buffer> <silent> y         VimpanelCopyNodes()

  map <buffer> <silent> <C-v>                 :call VimpanelPasteNodes()<CR>
  map <buffer> <silent> p                     :call VimpanelPasteNodes()<CR>

  nnoremap <buffer> <silent> a                :call VimpanelNewNode()<CR>
  nnoremap <buffer> <silent> dd               :call VimpanelDelNode()<CR>
  nnoremap <buffer> <silent> r                :call VimpanelMoveNode()<CR>

  map <buffer> <silent> x                     :call VimpanelExplorerMode()<CR>
  map <buffer> <silent> u                     :call vimpanel#upDir(0)<CR>
  map <buffer> <silent> c                     :call vimpanel#chRoot()<CR>
  map <buffer> <silent> ff                    :call VimpanelPathToClipboard()<CR>
  
  command! -buffer VimpanelDelNode call VimpanelDelNode()
  command! -buffer VimpanelMoveNode call VimpanelMoveNode()
  command! -buffer VimpanelCopyNode call VimpanelCopyNode()
  command! -buffer VimpanelPasteNodes call VimpanelPasteNodes()
  command! -buffer VimpanelNewNode call VimpanelNewNode()
  command! -buffer VimpanelRemove call VimpanelRemove()
  command! -buffer VimpanelPathToClipboard call VimpanelPathToClipboard()
endfunction

"""""""""""
" commands

command! -nargs=1 -complete=customlist,s:CompletePanelNames VimpanelCreate call VimpanelCreate('<args>')
command! -nargs=1 -complete=file Vimpanel call Vimpanel('<args>')
command! -nargs=1 -complete=file VimpanelAdd call VimpanelAdd('<args>')

command! -nargs=1 -complete=customlist,s:CompletePanelNames VimpanelEdit call VimpanelEdit('<args>')
command! -nargs=1 -complete=customlist,s:CompletePanelNames VimpanelOpen call VimpanelOpen('<args>', 0)
command! -nargs=1 -complete=customlist,s:CompletePanelNames VimpanelLoad call VimpanelLoad('<args>')
command! -nargs=? -complete=customlist,s:CompletePanelNames VimpanelToggleLeft call VimpanelToggle('<args>', 'topleft')
command! -nargs=? -complete=customlist,s:CompletePanelNames VimpanelToggleRight call VimpanelToggle('<args>', 'botright')
command! VimpanelRebuild call VimpanelRebuild()
command! VimpanelRefresh call VimpanelRefresh()
command! VimpanelSave call VimpanelSave()

command! -nargs=? -complete=customlist,s:CompleteSessionNames VimpanelSessionMake call VimpanelSessionMake('<args>')
command! -nargs=? -complete=customlist,s:CompleteSessionNames VimpanelSessionLoad call VimpanelSessionLoad('<args>')

augroup Vimpanel
  autocmd VimEnter * silent! autocmd! FileExplorer
  " capture directory edits (including drag n drop)
  autocmd BufAdd	* silent! call vimpanel#captureDir(expand("<amatch>"))
  " todo - use namespace scheme
  autocmd ColorScheme * silent! call vimpanel#hideMarkup()
augroup END

" todo - bug
" type :e D:\Junk
" E143: Autocommands unexpectedly deleted new buffer <8c>^C\Junk

" todo - minor bug
" for expanded dirs starting with a dot (.) , the dot is not highlighted

" todo - bug
" refreshin a tree does not preserve the same order of files
" globpath puts files starting with a capital letter at the beginning
