## Vimpanel

* Add any folder to the panel
* Each folder can be expanded independently
* You can stick files in there as well
* Drag and drop works too
* Create and display any number of panels
* Session support: find your panels and all other windows the way you left them when you exited Vim
* Filesystem operations, including file copying using visual selection
* Proper handling of Windows paths
* Explore the filesystem without constrains, in explorer mode
* Use it for project management, keeping bookmarks, notes or anything you like

Vimpanel builds upon [NERDTree](https://github.com/scrooloose/nerdtree), in an attempt to make the side panel
a place where you can keep your stuff organized, rather than just a file system explorer.

![screenshot](http://i.imgur.com/e6dIvrX.png)

### Getting started

Begin by creating a new panel with the `:VimpanelCreate` command.

    :VimpanelCreate myprojects
  
Load this panel in the current window with `:VimpanelLoad`

    :VimpanelLoad myprojects
  
Add entries to the panel with the `:Vimpanel` command.

    :Vimpanel D:\apps\myapp
  
The path you just added will act as a root and you can now expand and browse it. At any time you can add 
other roots to the panel.

To get rid of a root, select it and use the `:VimpanelRemove` command. This does not delete anything from
the filesystem, it just takes it off the panel.

Sort your panel entries by editing the Vimpanel storage file. The format of this file is painfully simple:
each line is an entry to the panel. There is a `:VimpanelEdit` command that makes this easier, by opening up 
that file:

    :VimpanelEdit mypanel
    
You will need to refresh the panel after this, with the `:VimpanelRefresh` command or the `<F5>` key. 
  
Inside the panel, focus on a single directory by entering explorer mode:

    x
    
In this mode, you can also move up a dir by using the `u` key, or change the root by using the `c` key.
Exit explorer mode at any time by pressing `x` again.

Inside the panel, several actions and filesystem operations are available.
Check the [full list](https://github.com/mihaifm/vimpanel#mappings-inside-the-panel) below.

When you're done working, save the state of you panel and everything else you have on the screen:

    :VimpanelSessionMake
    
This uses Vim's `mksession` command and some extra magic to save the state of your panels (the state 
is defined by which dirs are expanded and which are closed). You can optionally pass in a session name
to the command, if you want to keep multiple sessions with different names.

When you're ready to work again, load up that session using:

    :VimpanelSessionLoad
    
And that's about it. To make your life easier, you can use abbreviations or mappings for all these commands.
Here are some recommendations to put in your `vimrc`:

    cabbrev ss VimpanelSessionMake
    cabbrev sl VimpanelSessionLoad
    cabbrev vp Vimpanel
    cabbrev vl VimpanelLoad
    cabbrev vc VimpanelCreate
    cabbrev ve VimpanelEdit
    cabbrev vr VimpanelRemove
    
Tip: autocomplete works for panel names, so you can press `vl<space><tab>` and get a full list of panel names.

### Commands

    VimpanelCreate {name}

Creates a new panel with the specified name. Panel data is stored in a file called `name` located in `~/vimpanel/`    
This location is configurable with the `g:VimpanelStorage` option.

    Vimpanel {path}
    
Add the specified `path` as a root and rebuilds the panel.

    VimpanelAdd {path}

Add the specified `path` to the panel storage file (same as `:Vimpanel` but without the rebuild).

    VimpanelEdit {name}
    
Open the storage file associated with the panel. This file contains a list of all root paths contained by this panel.
You can edit this file, change the order of the roots or delete some entries. After editing, you need to run the
`:VimpanelRebuild` or `:VimpanelRefresh` commands to visually update the panel.

    VimpanelOpen {name}
    
Open the panel with the specified name in the current window. This will not expand any root nodes that the panel
may contain.

    VimpanelSave
    
Saves the state of the focused panel. The full path for all open nodes will be stored in a file called
`~/vimpanel/{name}_session`, where `{name}` is obviously the name of the panel. Note that you don't need to
save the panel after adding a root node with the `:Vimpanel` command, this is done automatically. 
The `:VimpanelSave` command only saves expanded directories.
    
    VimpanelLoad {name}
    
Loads the panel with the specified name in the current window, and restores its state. Nodes previously 
saved when the `:VimpanelSave` command was issued will be expanded.

    VimpanelRebuild
    
Rebuilds the active panel. This will read the entries from the panel storage file and will update the root
nodes accordingly.

    VimpanelRefresh
    
Rebuilds the panel and also refreshes all the open directories in the panel by reading data from the filesystem. 
Note that this command incorporates the functionality of the `:VimpanelRebuild` command.

    VimpanelToggleLeft [{name}]

Toggles the display of a panel in a window on the left side of the screen. If no panel name is given, the last
active panel is used.

    VimpanelToggleRight [{name}]

Same as `:VimpanelToggleLeft` but for the right side of the screen.

    VimpanelSessionMake [{name}]
    
Saves the current state of all the panels and all Vim windows and buffers. This is similar to `mksession` but it 
saves your panels as well. The session is stored in a script called `{name}.vim` located in the storage 
directory. If no name is provided, `default.vim` is used.

    VimpanelSessionLoad [{name}]
    
Restores Vim (panels, windows, buffers) to the state saved by the `:VimpanelSessionMake` command. If no name
is provided, it attempts to load the session called `default`.

### Mappings inside the panel

    <CR> or o or double-click       expand directory or open file
    <F5>                            refresh panel
    <F6>                            toggle the display of hidden files and folders
    t                               open file in new tab
    <C-c> or yy                     copy selected node (file or dir)
    <C-v> or p                      paste nodes
    dd                              delete node
    r                               rename node
    a                               add new node
    ff                              copy node path to clipboard
    
You can use visual selection (`v` or `V`) to grab some files and then press `<C-c>` or `y` to copy them. 
Paste them anywhere else with the `p` key.

### Explorer mode

Toggle explorer mode by selecting a folder and pressing the `x` key. In this mode you can freely explore the filesystem. 
The selected folder will become the root of the tree, but you can change to another root using the `c` key or explore the
parent directory using the `u` key (move up).

Why is this mode needed? For 2 main reasons:

* to keep focus on a single tree
* for the ability to navigate up in the folder hierarchy

### Config

    g:VimpanelStorage

A string representing the path to the storage folder. This folder holds all the panel data and session information.   
Default: `~/vimpanel`

    g:VimpanelCompact 

Set this to 1 to remove the extra blank line that separates trees.   
Default: 0

    g:VimpanelWinSize

Initial size (in columns) of the vimpanel window.    
Default: 31

    g:VimpanelShowHidden

Set this to 0 to hide the files and folders starting with `.` for all the panels.    
Default: 1
