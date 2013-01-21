syn match VimpanelFlag #\~#
syn match VimpanelFlag #\[RO\]#

" highlighting for the ~/+ symbols for the directory nodes
syn match VimpanelClosable #\~\<#
syn match VimpanelClosable #\~\.#
syn match VimpanelOpenable #+\<#
syn match VimpanelOpenable #+\.#he=e-1

" highlighting for the tree structural parts
syn match VimpanelPart #|#
syn match VimpanelPart #`#
syn match VimpanelPartFile #[|`]-#hs=s+1 contains=VimpanelPart

" highlighting for readonly files
syn match VimpanelRO #.*\[RO\]#hs=s+2 contains=VimpanelFlag,VimpanelPart,VimpanelPartFile

" highlighting for sym links
syn match VimpanelLink #[^-| `].* -> # contains=VimpanelBookmark,VimpanelOpenable,VimpanelClosable,VimpanelDirSlash

" highlighing for directory nodes and file nodes
syn match VimpanelDirSlash #\v/|\\#
syn match VimpanelDir #[^-| `].*# contains=VimpanelLink,VimpanelDirSlash,VimpanelOpenable,VimpanelClosable,VimpanelEndSlash
syn match VimpanelExecFile  #[|` ].*\*\($\| \)# contains=VimpanelLink,VimpanelPart,VimpanelRO,VimpanelPartFile,VimpanelBookmark
syn match VimpanelFile  #|-.*# contains=VimpanelLink,VimpanelPart,VimpanelRO,VimpanelPartFile,VimpanelBookmark,VimpanelExecFile
syn match VimpanelFile  #`-.*# contains=VimpanelLink,VimpanelPart,VimpanelRO,VimpanelPartFile,VimpanelBookmark,VimpanelExecFile
syn match VimpanelEndSlash #\v(/|\\)\s*$#
syn match VimpanelRoot #^[</A-Za-z].*$# contains=VimpanelEndSlash


hi def link VimpanelFile Normal
hi def link VimpanelExecFile Title
hi def link VimpanelDirSlash Identifier

hi def link VimpanelDir Directory
hi def link VimpanelUp Directory
hi def link VimpanelRoot Statement
hi def link VimpanelLink Macro

hi def link VimpanelRO WarningMsg

hi def link VimpanelClosable ignore
hi def link VimpanelFlag ignore
hi def link VimpanelOpenable ignore
hi def link VimpanelEndSlash ignore
hi def link VimpanelPart ignore
hi def link VimpanelPartFile ignore

call vimpanel#hideMarkup()
