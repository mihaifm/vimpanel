let s:TreeFileNode = {}
let g:VimpanelTreeFileNode = s:TreeFileNode

function! s:TreeFileNode.activate(...)
  call self.open(a:0 ? a:1 : {})
endfunction

" initializes self.parent if it isn't already
function! s:TreeFileNode.cacheParent()
  if empty(self.parent)
    let parentPath = self.path.getParent()
    if parentPath.equals(self.path)
      throw "Vimpanel.CannotCacheParentError: already at root"
    endif
    let self.parent = s:TreeFileNode.New(parentPath)
  endif
endfunction

function! s:TreeFileNode.copy(dest)
  call self.path.copy(a:dest)
endfunction

" removes this node from the tree and calls the Delete method for its path obj
function! s:TreeFileNode.delete()
    call self.path.delete()
    call self.parent.removeChild(self)
endfunction

" returns a string that specifies how the node should be represented as a string
function! s:TreeFileNode.displayString()
  return self.path.displayString()
endfunction

" compares this treenode to the input treenode and returns 1 if they are the same node
" Use this method instead of ==  because sometimes when the treenodes contain
" many children, vim seg faults when doing ==
function! s:TreeFileNode.equals(treenode)
  return self.path.str() ==# a:treenode.path.str()
endfunction

" returns self if this node.path.Equals the given path.
" returns {} if not equal.
" path: the path object to compare against
function! s:TreeFileNode.findNode(path)
  if a:path.equals(self.path)
    return self
  endif
  return {}
endfunction

" returns the line number this node is rendered on, or -1 if it isn't rendered
function! s:TreeFileNode.getLineNum()
  let totalLines = line("$")

  let fullpath = self.path.str({'format': 'UI'})

  let lnum = 1

  let pathcomponents = []
  let curPathComponent = 0

  while lnum > 0
    let curLine = getline(lnum)

    if vimpanel#blank(curLine)
      let lnum = lnum + 1
      if lnum >= totalLines + 1
        return -1
      else
        continue
      endif
    endif

    if curLine !~# vimpanel#nonRootExpr()
      let root_data = vimpanel#rootDataFromLine(lnum)

      if fullpath ==? root_data.root.path.str({'format': 'UI'})
        return lnum
      else
        let lnum = lnum + 1
        let curLine = root_data.root.path.str({'format': 'UI'})
        let pathcomponents = [substitute(curLine, '\v(\\|/) *$', '', '')]
        let curPathComponent = 1
        continue
      endif
    endif

    let indent = vimpanel#indentLevelFor(curLine)
    if indent ==# curPathComponent
      let curLine = vimpanel#stripMarkupFromLine(curLine, 1)

      let curPath =  join(pathcomponents, g:VimpanelPath.Slash()) . g:VimpanelPath.Slash() . curLine
      if stridx(fullpath, curPath, 0) ==# 0
        if fullpath ==# curPath || strpart(fullpath, len(curPath) - 1, 1) ==# g:VimpanelPath.Slash()
          let curLine = substitute(curLine, '\v(\\|/) *$', '', '')
          call add(pathcomponents, curLine)
          let curPathComponent = curPathComponent + 1

          if fullpath ==# curPath
            return lnum
          endif
        endif
      endif
    endif

    let lnum = lnum + 1
    if lnum >= totalLines + 1
      return -1
    endif

  endwhile
  return -1
endfunction

" returns 1 if this node should be visible according to the tree filters and
" hidden file filters (and their on/off status)
function! s:TreeFileNode.isVisible()
  return !self.path.ignore()
endfunction

" returns 1 if this node is a root
function! s:TreeFileNode.isRoot()
  for root in b:tree_objects
    if self.equals(root)
      return 1
    endif
  endfor
  return 0
endfunction

" make this node the root of the tree
function! s:TreeFileNode.makeRoot()
  if !self.path.isDirectory
    return
  endif

  call self.open()
  let b:tree_objects = [self]
endfunction

" returns a new TreeNode object with the given path and parent
" path: a path object representing the full filesystem path to the file/dir that the node represents
function! s:TreeFileNode.New(path)
  if a:path.isDirectory
    return g:VimpanelTreeDirNode.New(a:path)
  else
    let newTreeNode = copy(self)
    let newTreeNode.path = a:path
    let newTreeNode.parent = {}
    return newTreeNode
  endif
endfunction

function! s:TreeFileNode.open(...)
  let opts = a:0 ? a:1 : {}
  let opener = g:VimpanelOpener.New(self.path, opts)
  call opener.open(self)
endfunction

" places the cursor on the line number this node is rendered on
" isJump: 1 if this cursor movement should be counted as a jump by vim
" recurseUpward: try to put the cursor on the parent if the this node isn't visible
function! s:TreeFileNode.putCursorHere(isJump, recurseUpward)
  let ln = self.getLineNum()
  if ln != -1
    if a:isJump
      mark '
    endif
    call cursor(ln, col("."))
  else
    if a:recurseUpward
      let node = self
      while node != {} && node.getLineNum() ==# -1
        let node = node.parent
        call node.open()
      endwhile
      call vimpanel#renderPanel()
      call node.putCursorHere(a:isJump, 0)
    endif
  endif
endfunction

function! s:TreeFileNode.refresh()
  call self.path.refresh()
endfunction

" calls the rename method for this node's path obj
function! s:TreeFileNode.rename(newName)
  let newName = substitute(a:newName, '\(\\\|\/\)$', '', '')
  let root = self.getRoot()

  call self.path.rename(newName)
  call self.parent.removeChild(self)

  let parentPath = self.path.getParent()
  let newParent = root.findNode(parentPath)

  if newParent != {}
    call newParent.createChild(self.path, 1)
    call newParent.refresh()
  endif
endfunction

" returns the root object for the current node
function! s:TreeFileNode.getRoot()
  let ln = self.getLineNum()
  let root_data = vimpanel#rootDataFromLine(ln)
  return root_data.root
endfunction

" returns a string representation for this tree to be rendered in the view
function! s:TreeFileNode.renderToString()
  return self._renderToString(0, 0, [], 0)
endfunction

" renders this node
" depth: the current depth in the tree for this call
" drawText: 1 if we should actually draw the line for this node (if 0 then the
"   child nodes are rendered only)
" vertMap: a binary array that indicates whether a vertical bar should be draw
"   for each depth in the tree
" isLastChild:true if this curNode is the last child of its parent
function! s:TreeFileNode._renderToString(depth, drawText, vertMap, isLastChild)
  let output = ""
  if a:drawText ==# 1

    let treeParts = ''

    "get all the leading spaces and vertical tree parts for this line
    if a:depth > 1
      for j in a:vertMap[0:-2]
        if g:VimpanelDirArrows
          let treeParts = treeParts . '  '
        else
          if j ==# 1
            let treeParts = treeParts . '| '
          else
            let treeParts = treeParts . '  '
          endif
        endif
      endfor
    endif

    " get the last vertical tree part for this line which will be different
    "if this node is the last child of its parent
    if !g:VimpanelDirArrows
      if a:isLastChild
        let treeParts = treeParts . '`'
      else
        let treeParts = treeParts . '|'
      endif
    endif

    " smack the appropriate dir/file symbol on the line before the file/dir name itself
    if self.path.isDirectory
      if self.isOpen
        if g:VimpanelDirArrows
          let treeParts = treeParts . '▾ '
        else
          let treeParts = treeParts . '~'
        endif
      else
        if g:VimpanelDirArrows
          let treeParts = treeParts . '▸ '
        else
          let treeParts = treeParts . '+'
        endif
      endif
    else
      if g:VimpanelDirArrows
        let treeParts = treeParts . '  '
      else
        let treeParts = treeParts . '-'
      endif
    endif
    let line = treeParts . self.displayString()

    let output = output . line . "\n"
  endif

  " if the node is an open dir, draw its children
  if self.path.isDirectory ==# 1 && self.isOpen ==# 1

    let childNodesToDraw = self.getVisibleChildren()
    if len(childNodesToDraw) > 0

      " draw all the nodes children except the last
      let lastIndx = len(childNodesToDraw)-1
      if lastIndx > 0
        for i in childNodesToDraw[0:lastIndx-1]
          let output = output . i._renderToString(a:depth + 1, 1, add(copy(a:vertMap), 1), 0)
        endfor
      endif

      " draw the last child, indicating that it IS the last
      let output = output . childNodesToDraw[lastIndx]._renderToString(a:depth + 1, 1, add(copy(a:vertMap), 0), 1)
    endif
  endif

  if a:depth == 0
    if !g:VimpanelCompact
      let output .= "\n"
    endif
  endif

  return output
endfunction

" save the state of this node (open/closed) 
" and the state of all its children to a global list
function! s:TreeFileNode.saveState()
  call self._saveState(0)
endfunction

function! s:TreeFileNode._saveState(depth)
  if self.path.isDirectory && self.isOpen
    call add(g:vimpanel#state_output_list, self.path.str())
    let childNodes = self.getVisibleChildren()
    for i in childNodes
      call i._saveState(a:depth + 1)
    endfor
  endif
endfunction

" restore the state of this node and its children from a global list
" of open paths
function! s:TreeFileNode.restoreState()
  call self._restoreState()
endfunction

function! s:TreeFileNode._restoreState()
  if self.path.isDirectory
    let pidx = index(g:vimpanel#state_input_list, tolower(self.path.str())) 
    if pidx !=# -1
      call self.open()
      call remove(g:vimpanel#state_input_list, pidx)
      let childNodes = self.getVisibleChildren()
      for c in childNodes
        call c._restoreState()
      endfor
    endif
  endif
endfunction

