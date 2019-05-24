let s:TreeDirNode = {}

if exists("g:VimpanelTreeFileNode")
  let s:TreeDirNode = copy(g:VimpanelTreeFileNode)
else
  finish
endif

let g:VimpanelTreeDirNode = s:TreeDirNode

unlet s:TreeDirNode.activate
function! s:TreeDirNode.activate(...)
  let opts = a:0 ? a:1 : {}
  call self.toggleOpen(opts)
  call vimpanel#renderPanel()
endfunction

" adds the given treenode to the list of children for this node
" treenode: the node to add
" inOrder: 1 if the new node should be inserted in sorted order
function! s:TreeDirNode.addChild(treenode, inOrder)
  call add(self.children, a:treenode)
  let a:treenode.parent = self

  if a:inOrder
    call self.sortChildren()
  endif
endfunction

" closes this directory
function! s:TreeDirNode.close()
  let self.isOpen = 0
endfunction

" closes all the child dir nodes of this node
function! s:TreeDirNode.closeChildren()
  for i in self.children
    if i.path.isDirectory
      call i.close()
      call i.closeChildren()
    endif
  endfor
endfunction

" instantiates a new child node for this node with the given path. 
" the new nodes parent is set to this node.
" path: a Path object that this node will represent/contain
" inOrder: 1 if the new node should be inserted in sorted order
" returns: the newly created node
function! s:TreeDirNode.createChild(path, inOrder)
  let newTreeNode = g:VimpanelTreeFileNode.New(a:path)
  call self.addChild(newTreeNode, a:inOrder)
  return newTreeNode
endfunction

" will find one of the children (recursively) that has the given path
" path: a path object
unlet s:TreeDirNode.findNode
function! s:TreeDirNode.findNode(path)
  if a:path.equals(self.path)
    return self
  endif
  if stridx(a:path.str(), self.path.str(), 0) ==# -1
    return {}
  endif

  if self.path.isDirectory
    for i in self.children
      let retVal = i.findNode(a:path)
      if retVal != {}
        return retVal
      endif
    endfor
  endif
  return {}
endfunction

" returns the number of children this node has
function! s:TreeDirNode.getChildCount()
  return len(self.children)
endfunction

" returns child node of this node that has the given path or {} if no such node exists
" this function doesnt not recurse into child dir nodes
" path: a path object
function! s:TreeDirNode.getChild(path)
  if stridx(a:path.str(), self.path.str(), 0) ==# -1
    return {}
  endif

  let index = self.getChildIndex(a:path)
  if index ==# -1
    return {}
  else
    return self.children[index]
  endif
endfunction

" returns the child at the given index
" indx: the index to get the child from
" visible: 1 if only the visible children array should be used, 0 if all the
"   children should be searched.
function! s:TreeDirNode.getChildByIndex(indx, visible)
  let array_to_search = a:visible? self.getVisibleChildren() : self.children
  if a:indx > len(array_to_search)
    throw "Vimpanel.InvalidArgumentsError: Index is out of bounds."
  endif
  return array_to_search[a:indx]
endfunction

" returns the index of the child node of this node that has the given path or
" -1 if no such node exists.
" this function doesnt not recurse into child dir nodes
" path: a path object
function! s:TreeDirNode.getChildIndex(path)
  if stridx(a:path.str(), self.path.str(), 0) ==# -1
    return -1
  endif

  " do a binary search for the child
  let a = 0
  let z = self.getChildCount()
  while a < z
    let mid = (a+z)/2
    let diff = a:path.compareTo(self.children[mid].path)

    if diff ==# -1
      let z = mid
    elseif diff ==# 1
      let a = mid+1
    else
      return mid
    endif
  endwhile
  return -1
endfunction

" returns the current node if it is a dir node, or else returns the current nodes parent
function! s:TreeDirNode.GetSelected()
  let currentDir = vimpanel#getSelectedNode()
  if currentDir != {} && !currentDir.isRoot()
    if currentDir.path.isDirectory ==# 0
      let currentDir = currentDir.parent
    endif
  endif
  return currentDir
endfunction

" returns the number of visible children this node has
function! s:TreeDirNode.getVisibleChildCount()
  return len(self.getVisibleChildren())
endfunction

" returns a list of children to display for this node, in the correct order
" returns: an array of treenodes
function! s:TreeDirNode.getVisibleChildren()
  let toReturn = []
  for i in self.children
    if i.path.ignore() ==# 0
      call add(toReturn, i)
    endif
  endfor
  return toReturn
endfunction

" returns 1 if this node has any childre, 0 otherwise
function! s:TreeDirNode.hasVisibleChildren()
  return self.getVisibleChildCount() != 0
endfunction

" removes all childen from this node and re-reads them
" silent: 1 if the function should not echo any "please wait" messages for
" large directories
" returns: the number of child nodes read
function! s:TreeDirNode._initChildren(silent)
  " remove all the current child nodes
  let self.children = []

  " get an array of all the files in the nodes dir
  let dir = self.path
  let globDir = dir.str({'format': 'Glob'})

  let old_wildignore = &wildignore
  if !g:VimpanelShowHidden
    set wildignore+=.*
  endif

  let filesStr = ''

  if g:VimpanelShowHidden
    let filesStr = globpath(globDir, '.*' . g:VimpanelPath.Slash()) . "\n"
  endif

  let filesStr .= globpath(globDir, '*' . g:VimpanelPath.Slash()) . "\n"
  let filesStr .= globpath(globDir, '*') . "\n"

  if g:VimpanelShowHidden
    let filesStr .= globpath(globDir, '.*')
  endif

  let &wildignore = old_wildignore

  let files = split(filesStr, "\n")

  " hack to move the directories at the beginning of the list
  " by removing duplicates from the globpath calls
  " this has better performance than doing self.sortChildren

  call filter(files, "!vimpanel#blank(v:val)")
  " clean the trailing slashes
  if vimpanel#OS_Windows()
    call map(files, "substitute(v:val, '\\\\$', '', '')")
  else
    call map(files, "substitute(v:val, '/$', '', '')")
  endif
  " remove duplicates from the second group of globpath calls
  let files = vimpanel#unique(files)
  " endhack

  if !a:silent && len(files) > vimpanel#notifThreshold() 
    call vimpanel#echo("Please wait, caching a large dir ...")
  endif

  let invalidFilesFound = 0
  for i in files
    " filter out the .. and . directories
    if i !~# '\v\/\.\.\/?$' && i !~# '\v\/*\.\/?$'

      " put the next file in a new node and attach it
      try
        let path = g:VimpanelPath.New(i)
        call self.createChild(path, 0)
      catch /^Vimpanel.\(InvalidArguments\|InvalidFiletype\)Error/
        let invalidFilesFound += 1
      endtry
    endif
  endfor

  " too slow, for some reason
  call self.sortChildren()

  if !a:silent && len(files) > vimpanel#notifThreshold() 
    call vimpanel#echo("Please wait, caching a large dir ... DONE (". self.getChildCount() ." nodes cached).")
  endif

  if invalidFilesFound
    call vimpanel#echoWarning(invalidFilesFound . " file(s) could not be loaded into the vimpanel")
  endif
  return self.getChildCount()
endfunction

" returns a new TreeNode object with the given path and parent
" path: a path object representing the full filesystem path to the file/dir that the node represents
unlet s:TreeDirNode.New
function! s:TreeDirNode.New(path)
  if a:path.isDirectory != 1
    throw "Vimpanel.InvalidArgumentsError: A TreeDirNode object must be instantiated with a directory Path object."
  endif

  let newTreeNode = copy(self)
  let newTreeNode.path = a:path

  let newTreeNode.isOpen = 0
  let newTreeNode.children = []

  let newTreeNode.parent = {}

  return newTreeNode
endfunction

" open the dir in the current tree or in a new tree elsewhere.
" if opening in the current tree, return the number of cached nodes.
unlet s:TreeDirNode.open
function! s:TreeDirNode.open(...)
  let opts = a:0 ? a:1 : {}

  if has_key(opts, 'where') && !empty(opts['where'])
    let opener = g:VimpanelOpener.New(self.path, opts)
    call opener.open(self)
  else
    let self.isOpen = 1
    if self.children ==# []
      return self._initChildren(0)
    else
      return 0
    endif
  endif
endfunction

" recursive open the dir if it has only one directory child
" returns: the level of opened directories
function! s:TreeDirNode.openAlong(...)
  let opts = a:0 ? a:1 : {}
  let level = 0

  let node = self
  while node.path.isDirectory
    call node.open(opts)
    let level += 1
    if node.getVisibleChildCount() == 1
      let node = node.getChildByIndex(0, 1)
    else
      break
    endif
  endwhile
  return level
endfunction

" opens this treenode and all of its children whose paths arent 'ignored'
" because of the file filters.
" this method is actually a wrapper for the OpenRecursively2 method which does the work
function! s:TreeDirNode.openRecursively()
  call self._openRecursively2(1)
endfunction

" opens this all children of this treenode recursively if either:
"   *they arent filtered by file filters
"   *a:forceOpen is 1
" forceOpen: 1 if this node should be opened regardless of file filters
function! s:TreeDirNode._openRecursively2(forceOpen)
  if self.path.ignore() ==# 0 || a:forceOpen
    let self.isOpen = 1
    if self.children ==# []
      call self._initChildren(1)
    endif

    for i in self.children
      if i.path.isDirectory ==# 1
        call i._openRecursively2(0)
      endif
    endfor
  endif
endfunction

unlet s:TreeDirNode.refresh
function! s:TreeDirNode.refresh()
  call self.path.refresh()

  " if this node was ever opened, refresh its children
  if self.isOpen || !empty(self.children)
    " go thru all the files/dirs under this node
    let newChildNodes = []
    let invalidFilesFound = 0
    let dir = self.path
    let globDir = dir.str({'format': 'Glob'})

    let old_wildignore = &wildignore
    if !g:VimpanelShowHidden
      set wildignore+=.*
    endif

    let filesStr = ''

    if g:VimpanelShowHidden
      let filesStr = globpath(globDir, '.*' . g:VimpanelPath.Slash()) . "\n"
    endif

    let filesStr .= globpath(globDir, '*' . g:VimpanelPath.Slash()) . "\n"
    let filesStr .= globpath(globDir, '*') . "\n"

    if g:VimpanelShowHidden
      let filesStr .= globpath(globDir, '.*')
    endif

    let &wildignore = old_wildignore

    let files = split(filesStr, "\n")

    call filter(files, "!vimpanel#blank(v:val)")
    if vimpanel#OS_Windows()
      call map(files, "substitute(v:val, '\\\\$', '', '')")
    else
      call map(files, "substitute(v:val, '/$', '', '')")
    endif
    let files = vimpanel#unique(files)

    for i in files
      " filter out the .. and . directories
      if i !~# '\v\/\.\.\/?$' && i !~# '\v\/*\.\/?$'
        try
          " create a new path and see if it exists in this nodes children
          let path = g:VimpanelPath.New(i)
          let newNode = self.getChild(path)
          if newNode != {}
            call newNode.refresh()
            call add(newChildNodes, newNode)

            " the node doesnt exist so create it
          else
            let newNode = g:VimpanelTreeFileNode.New(path)
            let newNode.parent = self
            call add(newChildNodes, newNode)
          endif

        catch /^Vimpanel.InvalidArgumentsError/
          let invalidFilesFound = 1
        endtry
      endif
    endfor

    " swap this nodes children out for the children we just read/refreshed
    let self.children = newChildNodes
    call self.sortChildren()

    if invalidFilesFound
      call vimpanel#echoWarning("some files could not be loaded into the vimpanel")
    endif
  endif
endfunction

" reveal the given path, i.e. cache and open all treenodes needed to display it in the UI
function! s:TreeDirNode.reveal(path)
  if !a:path.isUnder(self.path)
    throw "Vimpanel.InvalidArgumentsError: " . a:path.str() . " should be under " . self.path.str()
  endif

  call self.open()

  if self.path.equals(a:path.getParent())
    let n = self.findNode(a:path)
    call vimpanel#renderPanel()
    call n.putCursorHere(1,0)
    return
  endif

  let p = a:path
  while !p.getParent().equals(self.path)
    let p = p.getParent()
  endwhile

  let n = self.findNode(p)
  call n.reveal(a:path)
endfunction

" removes the given treenode from this nodes set of children
" treenode: the node to remove
" throws: a Vimpanel.ChildNotFoundError if the given treenode is not found
function! s:TreeDirNode.removeChild(treenode)
  for i in range(0, self.getChildCount()-1)
    if self.children[i].equals(a:treenode)
      call remove(self.children, i)
      return
    endif
  endfor

  throw "Vimpanel.ChildNotFoundError: child node was not found"
endfunction

" sorts the children of this node according to alphabetical order and the
" directory priority.
function! s:TreeDirNode.sortChildren()
  let CompareFunc = function("s:compareNodes")
  call sort(self.children, CompareFunc)
endfunction

" compare callback
function! s:compareNodes(n1, n2)
  return a:n1.path.compareTo(a:n2.path)
endfunction

" opens this directory if it is closed and vice versa
function! s:TreeDirNode.toggleOpen(...)
  let opts = a:0 ? a:1 : {}
  if self.isOpen ==# 1
    call self.close()
  else
    call self.openAlong(opts)
  endif
endfunction

" replaces the child of this with the given node (where the child node's full
" path matches a:newNode's fullpath). 
" The search for the matching node is  non-recursive
" newNode: the node to graft into the tree
function! s:TreeDirNode.transplantChild(newNode)
  for i in range(0, self.getChildCount()-1)
    if self.children[i].equals(a:newNode)
      let self.children[i] = a:newNode
      let a:newNode.parent = self
      break
    endif
  endfor
endfunction
