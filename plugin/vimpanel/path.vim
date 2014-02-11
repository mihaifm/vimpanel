let s:Path = {}
let g:VimpanelPath = s:Path

function! s:Path.AbsolutePathFor(str)
  let prependCWD = 0
  if vimpanel#OS_Windows()
    let prependCWD = a:str !~# '^.:\(\\\|\/\)' && a:str !~# '^\(\\\\\|\/\/\)'
  else
    let prependCWD = a:str !~# '^/'
  endif

  let toReturn = a:str
  if prependCWD
    let toReturn = getcwd() . s:Path.Slash() . a:str
  endif

  return toReturn
endfunction

function! s:Path.cacheDisplayString()
  let self.cachedDisplayString = self.getLastPathComponent(1)

  if self.isExecutable
    let self.cachedDisplayString = self.cachedDisplayString . '*'
  endif

  if self.isSymLink
    let self.cachedDisplayString .=  ' -> ' . self.symLinkDest
  endif

  if self.isReadOnly
    let self.cachedDisplayString .=  ' [RO]'
  endif
endfunction

function! s:Path.changeToDir()
  let dir = self.str({'format': 'Cd'})
  if self.isDirectory ==# 0
    let dir = self.getParent().str({'format': 'Cd'})
  endif

  try
    execute "cd " . dir
    call vimpanel#echo("CWD is now: " . getcwd())
  catch
    throw "Vimpanel.PathChangeError: cannot change CWD to " . dir
  endtry
endfunction

" compares this Path to the given path and returns 0 if they are equal, -1 if
" this Path is less than the given path, or 1 if it is greater.
" returns: 1, -1 or 0
function! s:Path.compareTo(path)
  let thisPath = self.getLastPathComponent(1)
  let thatPath = a:path.getLastPathComponent(1)

  " if the paths are the same then clearly we return 0
  if thisPath ==? thatPath
    return 0
  endif

  let thisSS = self.getSortOrderIndex()
  let thatSS = a:path.getSortOrderIndex()

  " compare the sort sequences, if they are different then the return
  " value is easy
  if thisSS < thatSS
    return -1
  elseif thisSS > thatSS
    return 1
  else
    " if the sort sequences are the same then compare the paths alphabetically
    let pathCompare = 0

    " files starting with . come last
    if thisPath =~ '^\.' && thatPath =~ '^\.' || thisPath !~ '^\.' && thatPath !~ '^\.'
      let pathCompare = thisPath <? thatPath
    else
      let pathCompare = thisPath >? thatPath
    endif

    if pathCompare
      return -1
    else
      return 1
    endif
  endif
endfunction

" factory method.
" creates a path object with the given path. The path is also created on the
" filesystem. If the path already exists, a Vimpanel.Path.Exists exception is
" thrown. If any other errors occur, a Vimpanel.Path exception is thrown.
function! s:Path.Create(fullpath)
  " bail if the a:fullpath already exists
  if isdirectory(a:fullpath) || filereadable(a:fullpath)
    throw "Vimpanel.CreatePathError: Directory Exists: '" . a:fullpath . "'"
  endif

  try

    " if it ends with a slash, assume its a dir create it
    if a:fullpath =~# '\(\\\|\/\)$'
      " whack the trailing slash off the end if it exists
      let fullpath = substitute(a:fullpath, '\(\\\|\/\)$', '', '')

      call mkdir(fullpath, 'p')

      " assume its a file and create
    else
      call writefile([], a:fullpath)
    endif
  catch
    throw "Vimpanel.CreatePathError: Could not create path: '" . a:fullpath . "'"
  endtry

  return s:Path.New(a:fullpath)
endfunction

" copies the file/dir represented by this Path to the given location
function! s:Path.copy(dest)
  if !s:Path.CopyingSupported()
    throw "Vimpanel.CopyingNotSupportedError: Copying is not supported on this OS"
  endif

  " let dest = s:Path.WinToUnixPath(a:dest)
  let dest = a:dest

  let cmd_prefix = ''
  if self.isDirectory
    let cmd_prefix = g:VimpanelCopyDirCmd
  else
    let cmd_prefix = g:VimpanelCopyFileCmd
  endif

  let cmd = cmd_prefix . " " . escape(self.str(), vimpanel#escapeChars()) . " " . escape(dest, vimpanel#escapeChars())
  
  call vimpanel#echo("executing: " . cmd)
  let success = system(cmd)
  if v:shell_error != 0
    throw "Vimpanel.CopyError: Could not copy ''". self.str() ."'' to: '" . a:dest . "'"
  endif
endfunction

" returns 1 if copying is supported for this OS
function! s:Path.CopyingSupported()
  return exists('g:VimpanelCopyFileCmd') && exists('g:VimpanelCopyDirCmd')
endfunction

" returns 1 if copy this path to the given location will cause files to overwritten
function! s:Path.copyingWillOverwrite(dest)
  if filereadable(a:dest)
    return 1
  endif

  if isdirectory(a:dest)
    let path = s:Path.JoinPathStrings(a:dest, self.getLastPathComponent(0))
    if filereadable(path)
      return 1
    endif
  endif
endfunction

" deletes the file represented by this path.
" deletion of directories is not supported
" throws: Vimpanel.Path.Deletion exceptions
function! s:Path.delete()
  if self.isDirectory
    let cmd = g:VimpanelRemoveDirCmd . " " . self.str({'escape': 1})
    let success = system(cmd)

    if v:shell_error != 0
      throw "Vimpanel.PathDeletionError: Could not delete directory: '" . self.str() . "'"
    endif
  else
    let success = delete(self.str())
    if success != 0
      throw "Vimpanel.PathDeletionError: Could not delete file: '" . self.str() . "'"
    endif
  endif
endfunction

" returns a string that specifies how the path should be represented as a string
function! s:Path.displayString()
  if self.cachedDisplayString ==# ""
    call self.cacheDisplayString()
  endif

  return self.cachedDisplayString
endfunction

function! s:Path.edit()
  exec "edit " . self.str({'format': 'Edit'})
endfunction

" if running windows, cache the drive letter for this path
function! s:Path.extractDriveLetter(fullpath)
  if vimpanel#OS_Windows()
    if a:fullpath =~ '^\(\\\\\|\/\/\)'
      "For network shares, the 'drive' consists of the first two parts of the path, i.e. \\boxname\share
      let self.drive = substitute(a:fullpath, '^\(\(\\\\\|\/\/\)[^\\\/]*\(\\\|\/\)[^\\\/]*\).*', '\1', '')
      let self.drive = substitute(self.drive, '/', '\', "g")
    else
      let self.drive = substitute(a:fullpath, '\(^[a-zA-Z]:\).*', '\1', '')
    endif
  else
    let self.drive = ''
  endif
endfunction

" returns 1 if this path points to a location that is readable or is a directory
function! s:Path.exists()
  let p = self.str()
  return filereadable(p) || isdirectory(p)
endfunction

" returns this path if it is a directory, else this path's parent.
" returns: a Path object
function! s:Path.getDir()
  if self.isDirectory
    return self
  else
    return self.getParent()
  endif
endfunction

" returns a new path object for this path's parent
function! s:Path.getParent()
  if vimpanel#OS_Windows()
    let path = self.drive . '\' . join(self.pathSegments[0:-2], '\')
  else
    let path = '/'. join(self.pathSegments[0:-2], '/')
  endif

  return s:Path.New(path)
endfunction

" gets the last part of this path.
" dirSlash: if 1 then a trailing slash will be added to the returned value for directory nodes
function! s:Path.getLastPathComponent(dirSlash)
  if empty(self.pathSegments)
    return ''
  endif
  let toReturn = self.pathSegments[-1]
  if a:dirSlash && self.isDirectory
    let toReturn = toReturn . s:Path.Slash()
  endif
  return toReturn
endfunction

" returns the index of the pattern for sort order
function! s:Path.getSortOrderIndex()
  if self.isDirectory 
    return 0
  endif
  return 1
endfunction

" obsolete: ignoring should be done via wildignore
function! s:Path.ignore()
  return 0
endfunction

" returns 1 if this path is somewhere under the given path in the filesystem.
" path: should be a dir
function! s:Path.isUnder(path)
  if a:path.isDirectory == 0
    return 0
  endif

  let this = self.str()
  let that = a:path.str()
  return stridx(this, that . s:Path.Slash()) == 0
endfunction

function! s:Path.JoinPathStrings(...)
  let components = []
  for i in a:000
    let components = extend(components, split(i, '/'))
  endfor
  return '/' . join(components, '/')
endfunction

" determines whether 2 path objects are equal:
" they are equal if the paths they represent are the same
" path: the other path obj to compare this with
function! s:Path.equals(path)
  return self.str() ==# a:path.str()
endfunction

" the Constructor for the Path object
function! s:Path.New(path)
  let newPath = copy(self)

  call newPath.readInfoFromDisk(s:Path.AbsolutePathFor(a:path))

  let newPath.cachedDisplayString = ""

  return newPath
endfunction

" return the slash to use for the current OS
function! s:Path.Slash()
  return vimpanel#OS_Windows() ? '\' : '/'
endfunction

" invokes the vim resolve() function and return the result
" this is necessary because in some versions of vim resolve() removes trailing
" slashes while in other versions it doesn't. This always removes the trailing slash
function! s:Path.Resolve(path)
  let tmp = resolve(a:path)
  return tmp =~# '.\+/$' ? substitute(tmp, '/$', '', '') : tmp
endfunction

" throws Vimpanel.Path.InvalidArguments exception.
function! s:Path.readInfoFromDisk(fullpath)
  call self.extractDriveLetter(a:fullpath)

  let fullpath = s:Path.WinToUnixPath(a:fullpath)

  if getftype(fullpath) ==# "fifo"
    throw "Vimpanel.InvalidFiletypeError: Cant handle FIFO files: " . a:fullpath
  endif

  let self.pathSegments = split(fullpath, '/')

  let self.isReadOnly = 0
  if isdirectory(a:fullpath)
    let self.isDirectory = 1
  elseif filereadable(a:fullpath)
    let self.isDirectory = 0
    let self.isReadOnly = filewritable(a:fullpath) ==# 0
  else
    throw "Vimpanel.InvalidArgumentsError: Invalid path = " . a:fullpath
  endif

  let self.isExecutable = 0
  if !self.isDirectory
    let self.isExecutable = getfperm(a:fullpath) =~# 'x'
  endif

  " grab the last part of the path (minus the trailing slash)
  let lastPathComponent = self.getLastPathComponent(0)

  " get the path to the new node with the parent dir fully resolved
  let hardPath = s:Path.Resolve(self.strTrunk()) . '/' . lastPathComponent

  " if  the last part of the path is a symlink then flag it as such
  let self.isSymLink = (s:Path.Resolve(hardPath) != hardPath)
  if self.isSymLink
    let self.symLinkDest = s:Path.Resolve(fullpath)

    " if the link is a dir then slap a / on the end of its dest
    if isdirectory(self.symLinkDest)

      " we always wanna treat MS windows shortcuts as files for simplicity
      if hardPath !~# '\.lnk$'

        let self.symLinkDest = self.symLinkDest . '/'
      endif
    endif
  endif
endfunction

function! s:Path.refresh()
  call self.readInfoFromDisk(self.str())
  call self.cacheDisplayString()
endfunction

" renames this node on the filesystem
function! s:Path.rename(newPath)
  if a:newPath ==# ''
    throw "Vimpanel.InvalidArgumentsError: Invalid newPath for renaming = ". a:newPath
  endif

  let success =  rename(self.str(), a:newPath)
  if success != 0
    throw "Vimpanel.PathRenameError: Could not rename: '" . self.str() . "'" . 'to:' . a:newPath
  endif
  call self.readInfoFromDisk(a:newPath)
endfunction

" returns a string representation of this Path
" takes an optional dictionary param to specify how the output should be formatted
" the dict may have the following keys:
"  'format'
"  'escape'
"  'truncateTo'
"
" the 'format' key may have a value of:
"  'Cd' - a string to be used with the :cd command
"  'Edit' - a string to be used with :e :sp :new :tabedit etc
"  'UI' - a string used in the vimpanel UI
"  'Root' - a string to be used to render root paths
"
" the 'escape' key, if specified will cause the output to be escaped with shellescape()
"
" the 'truncateTo' key causes the resulting string to be truncated to the value
" 'truncateTo' maps to. A '<' char will be prepended.
function! s:Path.str(...)
  let options = a:0 ? a:1 : {}
  let toReturn = ""

  if has_key(options, 'format')
    let format = options['format']
    if has_key(self, '_strFor' . format)
      exec 'let toReturn = self._strFor' . format . '()'
    else
      raise 'Vimpanel.UnknownFormatError: unknown format "'. format .'"'
    endif
  else
    let toReturn = self._str()
  endif

  if vimpanel#has_opt(options, 'escape')
    let toReturn = shellescape(toReturn)
  endif

  if has_key(options, 'truncateTo')
    let limit = options['truncateTo']
    if len(toReturn) > limit
      let toReturn = "<" . strpart(toReturn, len(toReturn) - limit + 1)
    endif
  endif

  return toReturn
endfunction

function! s:Path._strForRoot()
  let slash = s:Path.Slash()

  let toReturn = slash . join(self.pathSegments, slash)
  if self.isDirectory && toReturn != slash
    let toReturn  = toReturn . slash
  endif
  let toReturn = self.drive . toReturn
  return toReturn
endfunction

function! s:Path._strForUI()
  let slash = s:Path.Slash()

  let toReturn = slash . join(self.pathSegments, slash)
  if self.isDirectory && toReturn != slash
    let toReturn  = toReturn . slash
  endif
  return toReturn
endfunction

" returns a string that can be used with :cd
function! s:Path._strForCd()
  return escape(self.str(), vimpanel#escapeChars())
endfunction

" returns: the string for this path that is suitable to be used with the :edit command
function! s:Path._strForEdit()
  let p = escape(self.str(), vimpanel#escapeChars())
  return p
endfunction

function! s:Path._strForGlob()
  let lead = s:Path.Slash()

  " if we are running windows then slap a drive letter on the front
  if vimpanel#OS_Windows()
    let lead = self.drive . '\'
  endif

  let toReturn = lead . join(self.pathSegments, s:Path.Slash())

  if !vimpanel#OS_Windows()
    let toReturn = escape(toReturn, vimpanel#escapeChars())
  endif
  return toReturn
endfunction

" gets the string path for this path object that is appropriate for the OS.
" EG, in windows c:\foo\bar
"     in *nix  /foo/bar
function! s:Path._str()
  let lead = s:Path.Slash()

  " if we are running windows then slap a drive letter on the front
  if vimpanel#OS_Windows()
    let lead = self.drive . '\'
  endif

  return lead . join(self.pathSegments, s:Path.Slash())
endfunction

" gets the path without the last segment on the end.
function! s:Path.strTrunk()
  return self.drive . '/' . join(self.pathSegments[0:-2], '/')
endfunction

" takes in a windows path and returns the unix equiv
" pathstr: the windows path to convert
function! s:Path.WinToUnixPath(pathstr)
  if !vimpanel#OS_Windows()
    return a:pathstr
  endif

  let toReturn = a:pathstr

  " remove the x:\ of the front
  let toReturn = substitute(toReturn, '^.*:\(\\\|/\)\?', '/', "")

  " remove the \\ network share from the front
  let toReturn = substitute(toReturn, '^\(\\\\\|\/\/\)[^\\\/]*\(\\\|\/\)[^\\\/]*\(\\\|\/\)\?', '/', "")

  " convert all \ chars to /
  let toReturn = substitute(toReturn, '\', '/', "g")

  return toReturn
endfunction
