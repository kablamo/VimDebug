" (c) eric johnson
" email: vimDebug at iijo dot org
" http://iijo.org

" --------------------------------------------------------------------
" Check prerequisites.

if ! has('perl') || ! has('signs') || ! has('autocmd')
   echo "VimDebug requires +perl, +signs, and +autocmd."
   finish
endif

" --------------------------------------------------------------------
" Configuration variables.

" Make sure all the values remain coherent if you change any.

   " The VimDebug start key. If this key is not already mapped in
   " normal mode (nmap), we will map it to start VimDebug. Otherwise,
   " to start the debugger one can call DBGRstart(...) or use the GUI
   " with its menu interface.
let s:cfg_startKey = "<F12>"

   " GUI menu label.
let s:cfg_menuLabel = '&Debugger'

   " Key bindings and menu settings. Each entry has: key, label, map.
let s:cfg_interface = [
 \ ['<F8>',       '&Next',                   'DBGRnext()'],
 \ ['<F7>',       '&Step in',                'DBGRstep()'],
 \ ['<F6>',       'Step &out',               'DBGRstepout()'],
 \ ['<F9>',       '&Continue',               'DBGRcont()'],
 \ ['<Leader>b',  'Set &breakpoint',         'DBGRsetBreakPoint()'],
 \ ['<Leader>c',  'C&lear breakpoint',       'DBGRclearBreakPoint()'],
 \ ['<Leader>ca', 'Clear &all breakpoints',  'DBGRclearAllBreakPoints()'],
 \ ['<Leader>x/', '&Print value',            'DBGRprint(inputdialog("Value to print: "))'],
 \ ['<Leader>x',  'Print &value here',       'DBGRprint(expand("<cword>"))'],
 \ ['<Leader>/',  'E&xecute command',        'DBGRcommand(inputdialog("Command to execute: "))'],
 \ ['<F10>',      '&Restart',                'DBGRrestart()'],
 \ ['<F11>',      '&Quit',                   'DBGRquit()'],
\]

   " Global variables. Each entry has: global variable name, default
   " value.
let s:cfg_globals = {
 \ 'g:DBGRconsoleHeight'  : 7,
 \ 'g:DBGRlineNumbers'    : 1,
 \ 'g:DBGRshowConsole'    : 1,
 \ 'g:DBGRdebugArgs'      : "",
\}

" --------------------------------------------------------------------
" This function will be called at the end of this script to
" initialize everything.

function! s:Initialize()

      " Colors and signs.
   hi hi_rev term=reverse cterm=reverse gui=reverse
   hi hi_non term=NONE    cterm=NONE    gui=NONE
   sign define s_invis
   sign define s_curs linehl=hi_rev
   sign define s_bkpt linehl=hi_non text=>>
   sign define s_both linehl=hi_rev text=>>

      " Initialize globals to their default value, unless they already
      " have a value.
   for [l:var, l:dft_val] in items(s:cfg.globals)
      exe
       \ "if ! exists('g:" . l:var . "') |" .
       \    "let " . l:var . " = '" . l:dft_val . "'| " .
       \ "endif"
   endfor

      " Make sure we exit the daemon when we leave Vim.
   autocmd VimLeave * call s:EnsureDaemonStopped()

      " Make the debugger launchable from the GUI toolbar.
   if has("gui_running")
      amenu ToolBar.-debuggerSep1- :
      amenu ToolBar.DBGRbug :call DBGRstart("")<cr>
      tmenu ToolBar.DBGRbug Start perl debugging session
   endif

   " Script variables.

   let s:daemon = {}
   let s:daemon.launched = 0
   let s:daemon.doneFile = ""

   let s:dbgr = {}

      " If the debugger is running, 1, else, 0.
   let s:dbgr.launched = 0

      " The number of the buffer where we will write debugger info.
   let s:dbgr.consoleBufNr  = 0

      " One entry for each breakpoint set. Keys come from
      " s:BufLynId(), and values are a dictionary having keys
      " 'bufNr', 'lynNr', 'cond'.
   let s:dbgr.bkpts = {}

      " Source files traversed by the debugger. Keys are file names,
      " values are dicts having keys 'bufNr', 'setNum', and 'hadBuf'.
   let s:dbgr.src = {}

      " Keys come from s:BufLynId(), values are dicts with mark name
      " keys 'cursor' and 'bkpt'.
   let s:dbgr.marks = {}

      " The cursor is where the debugger is poised to execute its next
      " instruction.
   let s:cursor = {}
   call s:ClearCursor()

   let s:interf = {}

      " See _VDsetInterface() for usage.
   let s:interf.state = 0

      " The user key bindings will be saved here if/when we launch
      " VimDebug. The entries of this list will be a bit different:
      " each one will be a two-element list of a key and of a
      " "saved-map" that will be provided by the 'savemap' vimscript.
   let s:interf.userSavedkeys = []

      " If the start key is defined and we can map to it, 1, else, 0.
   let s:interf.canMapStartKey =
    \ s:cfg.startKey != "" && empty(maparg(s:cfg.startKey, "n"))

      " Set up the start key and menus.
   call s:VDmapStartKey_DBGRstart()
   call s:VDmenuSet(0)

endfunction

" --------------------------------------------------------------------
" Debugger functions.

   " Start the debugger if it's not already running. If there is an
   " empty string argument, prompt for debugger arguments.
function! DBGRstart(...)
   if s:dbgrIsRunning
      echo "The debugger is already running."
      return
   endif
   try
      call s:Incantation(a:000)
      call s:StartVdd()
      " do after system() so nongui vim doesn't show a blank screen
      echo "\rstarting the debugger..."
      call s:SocketConnect()
      if has("autocmd")
         autocmd VimLeave * call DBGRquit()
      endif
      call DBGRopenConsole()
      redraw!
      call s:HandleCmdResult("connected to VimDebug daemon")
      call s:Handshake()
      call s:HandleCmdResult("started the debugger")
      call s:SocketConnect2()
      call s:HandleCmdResult2()
      call _VDsetInterface(1)
      call s:VDmapStartKey_toggleKeyBindings()
      let s:dbgrIsRunning = 1
      let s:programDone = 0
   catch /AbortLaunch/
      echo "Debugger launch aborted."
   catch /MissingVdd/
      echo "vdd is not in your PATH. Something went wrong with your VimDebug install."
   catch /.*/
      echo "Unexpected error: " . v:exception
   endtry
endfunction

function! DBGRnext()
   if !s:Copacetic()
      return
   endif
   echo "\rnext..."
   call s:SocketWrite("next")
   call s:HandleCmdResult()
endfunction

function! DBGRstep()
   if !s:Copacetic()
      return
   endif
   echo "\rstep..."
   call s:SocketWrite("step")
   call s:HandleCmdResult()
endfunction

function! DBGRstepout()
   if !s:Copacetic()
      return
   endif
   echo "\rstepout..."
   call s:SocketWrite("stepout")
   call s:HandleCmdResult()
endfunction

function! DBGRcont()
   if !s:Copacetic()
      return
   endif
   echo "\rcontinue..."
   call s:SocketWrite("cont")
   call s:HandleCmdResult()
endfunction

function! DBGRsetBreakPoint()
   if !s:Copacetic()
      return
   endif

   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = s:CreateId(l:bufNr, l:currLineNr)

   if count(s:breakPoints, l:id) == 1
      redraw! | echo "\rbreakpoint already set"
      return
   endif

   " tell vdd
   call s:SocketWrite("break:" . l:currLineNr . ':' . l:currFileName)

   call add(s:breakPoints, l:id)

   " check if a currentLine sign is already placed
   if (s:lineNumber == l:currLineNr)
      exe "sign unplace " . l:id
      exe "sign place " . l:id . " line=" . l:currLineNr . " name=both file=" . l:currFileName
   else
      exe "sign place " . l:id . " line=" . l:currLineNr . " name=breakPoint file=" . l:currFileName
   endif

   call s:HandleCmdResult("breakpoint set")
endfunction

function! DBGRclearBreakPoint()
   if !s:Copacetic()
      return
   endif

   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = s:CreateId(l:bufNr, l:currLineNr)

   if count(s:breakPoints, l:id) == 0
      redraw! | echo "\rno breakpoint set here"
      return
   endif

   " tell vdd
   call s:SocketWrite("clear:" . l:currLineNr . ':' . l:currFileName)

   call filter(s:breakPoints, 'v:val != l:id')
   exe "sign unplace " . l:id

   if(s:lineNumber == l:currLineNr)
      exe "sign place " . l:id . " line=" . l:currLineNr . " name=currentLine file=" . l:currFileName
   endif

   call s:HandleCmdResult("breakpoint disabled")
endfunction

function! DBGRclearAllBreakPoints()
   if !s:Copacetic()
      return
   endif

   call s:UnplaceBreakPointSigns()

   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = s:CreateId(l:bufNr, l:currLineNr)

   call s:SocketWrite("clearAll")

   " do this in case the last current line had a break point on it
   call s:UnplaceTheLastCurrentLineSign()                " unplace the old sign
   call s:PlaceCurrentLineSign(s:lineNumber, s:fileName) " place the new sign

   call s:HandleCmdResult("all breakpoints disabled")
endfunction

function! DBGRprint(...)
   if !s:Copacetic()
      return
   endif
   if a:0 > 0
      call s:SocketWrite("print:" . a:1)
      call s:HandleCmdResult()
   endif
endfunction

function! DBGRcommand(...)
   if !s:Copacetic()
      return
   endif
   echo ""
   if a:0 > 0
      call s:SocketWrite('command:' . a:1)
      call s:HandleCmdResult()
   endif
endfunction

function! DBGRrestart()
   if ! s:dbgrIsRunning
      echo "\rthe debugger is not running"
      return
   endif
   call s:SocketWrite("restart")
   " do after the system() call so that nongui vim doesn't show a blank screen
   echo "\rrestarting..."
   call s:UnplaceTheLastCurrentLineSign()
   redraw!
   call s:HandleCmdResult("restarted")
   let s:programDone = 0
endfunction

function! DBGRquit()
   if ! s:dbgrIsRunning
      echo "\rthe debugger is not running"
      return
   endif
   call _VDsetInterface(0)
   call s:VDmapStartKey_DBGRstart()

   " unplace all signs that were set in this debugging session
   call s:UnplaceBreakPointSigns()
   call s:UnplaceEmptySigns()
   call s:UnplaceTheLastCurrentLineSign()
   call s:SetNoNumber()

   call s:SocketWrite("quit")

   if has("autocmd")
     autocmd! VimLeave * call DBGRquit()
   endif

   " reinitialize script variables
   let s:lineNumber      = 0
   let s:fileName        = ""
   let s:bufNr           = 0
   let s:programDone     = 1

   let s:dbgrIsRunning = 0
   redraw! | echo "\rexited the debugger"

   " must do this last
   call DBGRcloseConsole()
endfunction

" --------------------------------------------------------------------
" Interface handling.

" These are the possible values of s:interfaceSetting, which tells us
" which key bindings are active and what the GUI menu looks like.
"
"  0 : User keys,     grayed out menu entries.
"  1 : VimDebug keys, active menu entries.
"  2 : User keys,     active menu entries, keys in  parentheses.

   " Request interface setting 0, 1, or 2, or 3 to toggle between 1
   " and 2.
function! _VDsetInterface(request)
   if a:request == 3
      if s:interfaceSetting == 0
         return
      endif
         " Toggle between 1 and 2.
      let l:want = 3 - s:interfaceSetting
   else
      let l:want = a:request
   endif

   if l:want == 0 || l:want == 2
      call s:VDrestoreKeyBindings()
   elseif l:want == 1
      call s:VDsetKeyBindings()
   else
      return
   endif

   call s:VDmenuSet(l:want)
   let s:interfaceSetting = l:want
endfunction

function! s:VDsetKeyBindings ()
   let s:userSavedkeys = []
   for l:data in s:cfg_interface
      let l:key = l:data[0]
      let l:map = l:data[2]
      call add(s:userSavedkeys, [l:key, savemap#save_map("n", l:key)])
      exec "nmap " . l:key . " :call " . l:map . "<cr>"
   endfor
   echo "VimDebug keys are active."
endfunction

function! s:VDrestoreKeyBindings ()
   for l:key_savedmap in s:userSavedkeys
      let l:key = l:key_savedmap[0]
      let l:saved_map = l:key_savedmap[1]
      if empty(l:saved_map['__map_info'][0]['normal'])
         exec "unmap " . l:key
      else
         call l:saved_map.restore()
      endif
   endfor
   let s:userSavedkeys = []
   echo "User keys are active."
endfunction

function! s:VDmenu_Start (on_or_off)
   if a:on_or_off == 1
      exec "amenu " . s:cfg_menuLabel . ".Start :call DBGRstart(\"\")<cr>"
   else
      exec "amenu disable " . s:cfg_menuLabel . ".Start"
   endif
endfunction

function! s:VDmenu_Toggle (on_or_off)
   if a:on_or_off == 1
      exec "amenu " . s:cfg_menuLabel . ".To&ggle\\ key\\ bindings :call _VDsetInterface(3)<cr>"
   else
      exec "amenu disable "  . s:cfg_menuLabel . ".To&ggle\\ key\\ bindings"
   endif
endfunction

   " Set up the GUI menu.
function! s:VDmenuSet (request)
   if ! has("gui_running")
      return
   endif
      " Delete the existing menu.
   try
      exec ":aunmenu " . s:cfg_menuLabel
   catch
   endtry

      " Insert the first three menu lines.
   call s:VDmenu_Start(1)
   call s:VDmenu_Toggle(1)
   exec "amenu ". s:cfg_menuLabel . ".-separ- :"
      " Disable the relevant one.
   if a:request == 0
      call s:VDmenu_Toggle(0)
   else
      call s:VDmenu_Start(0)
   endif

      " Build the other menu entries.
   for l:data in s:cfg_interface
      let l:key   = l:data[0]
      let l:label = l:data[1]
      let l:map   = l:data[2]
      let l:esc_label_key = escape(l:label . "\t" . l:key, " \t")
      try
         if a:request == 0
            exec "amenu disable " . s:cfg_menuLabel . "." . l:esc_label_key
         elseif a:request == 1
            exec "amenu " . s:cfg_menuLabel . "." . l:esc_label_key . " :call " . l:map . "<cr>"
         else
            let l:esc_label_no_key = escape(l:label . "\t(" . l:key . ")", " \t")
            exec "amenu " . s:cfg_menuLabel . "." . l:esc_label_no_key . " :call " . l:map . "<cr>"
         endif
      catch
      endtry
   endfor
endfunction

function! s:VDmapStartKey_DBGRstart ()
   if s:interf.canMapStartKey
      exe "nmap " . s:cfg.startKey . " :call DBGRstart(\"\")<cr>"
   endif
endfunction

function! s:VDmapStartKey_toggleKeyBindings ()
   if s:interf.canMapStartKey
      exe "nmap " . s:cfg.startKey . " :call _VDsetInterface(3)<cr>"
   endif
endfunction

" --------------------------------------------------------------------
" Marks and signs.

function! s:MarkLine(on_or_off, markName, bufNr, lynNr)
   if a:bufNr == 0 || a:lynNr == 0
      return
   endif
   let l:bufLineId = s:BufLynId(a:bufNr, a:lynNr)
   let l:want = get(s:dbgr.marks, l:bufLineId, {})
   if l:want == {}
      let l:want.cursor = 0
      let l:want.bkpt = 0
   endif
   let l:want[a:markName] = a:on_or_off
   let s:dbgr.marks[l:bufLineId] = l:want

   let l:sign =
    \     l:want.cursor &&   l:want.bkpt ? "s_both"
    \ : ! l:want.cursor &&   l:want.bkpt ? "s_bkpt"
    \ :   l:want.cursor && ! l:want.bkpt ? "s_curs"
    \ :   a:lynNr == 1                   ? "s_invis"
    \ : "none"
   call s:PlaceSign(l:sign, a:bufNr, a:lynNr)
endfunction

function! s:PlaceSign(signName, bufNr, lynNr)
   if a:signName == 'none'
      exe 'sign unplace ' . s:BufLynId(a:bufNr, a:lynNr)
      return
   endif
   let l:cmd = "sign place " . s:BufLynId(a:bufNr, a:lynNr)
    \ . " line="   . a:lynNr
    \ . " name="   . a:signName
    \ . " buffer=" . a:bufNr
   exe l:cmd
endfunction

" --------------------------------------------------------------------
" The arguments should be provided by reading debugger output,
" ensuring a bit of sanity.

function! s:SetCursorLine(fileName, lynNr)

      " Note previous cursor position.
   let l:prev_bufNr = s:cursor.bufNr
   let l:prev_lynNr = s:cursor.lynNr

      " Note the position of the text cursor in the code window.
   let l:prev_bufNr = s:cursor.bufNr
   let l:prev_lynNr = s:cursor.lynNr

      " Turn off previous cursor line hilight.
   call s:MarkLine(0, "cursor", s:cursor.bufNr, s:cursor.lynNr)

      " Set current cursor values.
   let s:cursor.bufNr = s:SrcBufNr(a:fileName)
   let s:cursor.lynNr = a:lynNr

      " Turn on current cursor line hilight.
   call s:MarkLine(1, "cursor", s:cursor.bufNr, s:cursor.lynNr)

   let l:str = 'call s:MarkLine(1, "cursor", ' . s:cursor.bufNr . ', ' . s:cursor.lynNr . ')'
   if s:cursor.snapped
      call VDfocusCursor()
   endif
endfunction

" --------------------------------------------------------------------
" When the debugger moves to some source code, that code might be in
" another file. This function makes sure that such a file is loaded
" and returns its buffer number.

function! s:SrcBufNr(srcFileName)
      " Return it if we had it stored.
   let l:dbgrSrc = get(s:dbgr.src, a:srcFileName, {})
   if l:dbgrSrc != {}
      return l:dbgrSrc.bufNr
   endif
   let s:dbgr.src[a:srcFileName] = {}

      " If the file already in some buffer, use that.
   let l:bufNr = bufnr(a:srcFileName)
   if l:bufNr != -1
      let s:dbgr.src[a:srcFileName].hadBuf = 1
   else
      let s:dbgr.src[a:srcFileName].hadBuf = 0
         " We need to load the buffer, but let's do it discreetly.
      wincmd n
      exe ":e! " . a:srcFileName
      let l:bufNr = bufnr('')
      wincmd w
      wincmd o
   endif
   let s:dbgr.src[a:srcFileName].bufNr = l:bufNr

   let s:dbgr.src[a:srcFileName].setNum = &number

   exe "setl " . (g:DBGRsetNumber ? "" : "no") . "number"

      " Make the buffer open its two-column-wide signs space right
      " away rather than having the text annoyingly shift right and
      " left as cursor and breakpoint signs are added and removed.
   call s:PlaceSign('s_invis', l:bufNr, 1)
   return l:bufNr
endfunction

" --------------------------------------------------------------------
" Communications with daemon.

function! s:EnsureDaemonLaunched()
   if s:daemon.launched
      return
   endif
   perl << EOF
      use Vim::Debug::Daemon;
         # Initialized here, this Vim::Debug::Talker reference is
         # supplied by the starting daemon and used to communicate
         # with it. A package (main::) variable like this one, when
         # used in vimscript, contrary to perl lexicals, retains its
         # value across perl vimscript snippets; we consider it to be
         # a kind of "global" and thus prefix it with "g".
      $gTalker = Vim::Debug::Daemon->start;
         # Now we fork. The child will run the daemon, and the parent
         # will drop POE and from now on use $gTalker to communicate
         # with the daemon.
      $gPid = fork;
      if (! defined $gPid) {
         VIM::DoCommand(qq<echo "Couldn't fork daemon.">);
      }
      elsif ($gPid == 0) {
            # Child process.
         Vim::Debug::Daemon->run;
      }
      else {
            # Parent process.
         POE::Kernel->stop;
         VIM::DoCommand("let s:daemon.doneFile = '" . $gTalker->done_file . "'");
         VIM::DoCommand("let s:daemon.launched = 1");
      }
EOF
   if ! s:daemon.launched
      throw /CouldntLaunchDaemon/
   endif
endfunction

function! s:LaunchDebugger(language, fileName, debuggerArgs)
   let l:cmd =
    \ "start:" . a:language .
    \      ":" . a:fileName .
    \      ":" . a:debuggerArgs
   perl $gTalker->send((VIM::Eval('l:cmd'))[1]);
   let l:heard = s:TalkerRecv()

   call s:ConsolePrint(l:heard.output)

   if l:heard.status == "ready"
      if len(l:heard.line) > 0
         call s:SetCursorLine(l:heard.file, l:heard.line)
      endif
   else
      if l:heard.status == "compiler_error"
         echo "The program did not compile."
      else
         echo "Unexpected status '" . l:heard.status . "' while attempting to start debugger."
      endif
   endif
      " Set up the interface.
   call _VDsetInterface(1)
   call s:VDmapStartKey_toggleKeyBindings()
   call s:VDsetToolBar(1)
   let s:dbgr.launched = 1
   call VDresetGeom()
endfunction

function! s:VddCmd(cmd, msg)
   if s:dbgr.launched != 1
      echo "The debugger is not running."
      return 0
   endif

   if a:cmd =~ '\v^(next|stepin|stepout|cont|break|clear|clearAll|print|command)'
      if s:cursor.bufNr == 0
         echo "The application being debugged is not running."
         return 0
      endif
   elseif a:cmd !~ '^\v(restart|stop)'
      echo "Unknown command '" . a:cmd . "'."
      return 0
   endif

   echo a:msg . "..."
   perl $gTalker->send((VIM::Eval('a:cmd'))[1]);
   let l:heard = s:TalkerRecv()

   if l:heard.status == "ready"
      call s:ConsolePrint(l:heard.output)
      if len(l:heard.line) > 0
         call s:SetCursorLine(l:heard.file, l:heard.line)
      endif

   elseif l:heard.status == "app_exited"
      call s:ConsolePrint(l:heard.output)
      call s:ClearCursor()
      redraw! | echo "The application being debugged terminated."

   elseif l:heard.status == "runtime_error"
      call s:ConsolePrint(l:heard.output)
      call s:ClearCursor()
      redraw! | echo "There was a runtime error."

   else
      call s:ErrorReport("e001", "Unexpected status '" . l:heard.status . "'.")

   endif
      " Erases any currently echoed message.
   redraw!
   return 1
endfunction

function! s:TalkerRecv()
   try
         " A blocking loop. The daemon signals that it's done sending
         " a msg by touching the file. While the debugger remains
         " busy, the user can interrupt the operation.
      while !filereadable(s:daemon.doneFile)
         sleep 200m
      endwhile
   perl << EOF
         # Split the data into an array, escaping single quotes. The
         # apostrophe in the comment is to balance the last one in the
         # regex to obtain proper syntax highlighting :-(
      my $data = $gTalker->recv;
      $data->{$_} =~ s|'|''|g for keys %$data;    # '
      VIM::DoCommand("
         return {
          \\ 'status' : '$data->{status}',
          \\ 'file'   : '$data->{file}',
          \\ 'line'   : '$data->{line}',
          \\ 'result' : '$data->{result}',
          \\ 'output' : '$data->{output}',
         \\}
      ");
EOF
   catch
      echo "Interrupted!"
      perl $gTalker->interrupt
      call s:TalkerRecv()
   endtry
endfunction

function! s:ConsolePrint(msg)
      " Open the console if needed.
   if s:dbgr.consoleBufNr == 0
      set hidden
      new Debugger_console
      normal iDebugger console
      let s:dbgr.consoleBufNr = bufnr('')
      setl number
      set buftype=nofile
      wincmd c
   endif

   let l:saveBuf = bufnr('')
   exe "buffer " . s:dbgr.consoleBufNr
   let l:saveReg = @x
   let @x = a:msg
   silent exe 'normal G"xpG'
   let @x = l:saveReg
   exe "buffer " . l:saveBuf
      " If the console window is visible, move to its last line.
   let l:consoleWinNr = bufwinnr(s:dbgr.consoleBufNr)
   if l:consoleWinNr >= 1
      let l:saveWinNr = bufwinnr(l:saveBuf)
      exe bufwinnr(s:dbgr.consoleBufNr) . " wincmd w"
      normal G
      exe l:saveWinNr . " wincmd w"
   endif
endfunction

function! s:EnsureDaemonStopped()
   if s:daemon.launched
      perl $gTalker->send('quit_daemon')
      if s:dbgr.launched
         perl $gTalker->send('stop')
      endif
   endif
endfunction

" --------------------------------------------------------------------
" User commands.

command! -nargs=* VDstart      call DBGRstart(<f-args>)
command! -nargs=0 VDtoggleKeys call _VDsetInterface(3)

" --------------------------------------------------------------------
" Initialize everything.

call s:Initialize()

