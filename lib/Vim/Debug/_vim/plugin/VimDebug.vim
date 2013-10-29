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

   " Start the debugger if it's not already running. If there are no
   " arguments, no debugger arguments will be passed. If the first
   " argument is an empty string, prompt for debugger arguments, else
   " pass the first argument as a space-delimited debugger arguments
   " string.
function! DBGRstart(...)
   if s:dbgr.launched
      return
   endif
   try
         " Make sure we have a file name to pass to the debugger.
      let l:launchFileName = bufname("%")
      if l:launchFileName == ""
         throw "NoFileName"
      endif
      if ! filereadable(l:launchFileName)
         throw "NoSuchFileYet"
      endif

         " Okay, we have a candidate file for the debugger, let's
         " launch the daemon.
      call s:EnsureDaemonLaunched()

         " Note the launch file's buffer number and 'number' setting.
      let s:dbgr.launchFile = {}
      let s:dbgr.launchFile.bufNr = bufnr("%")
      let s:dbgr.launchFile.setNum = &number

         " Get arguments for the debugger and launch it.
      let l:nb_dbgr_args = len(a:000)
      let l:cancelStr = "ccanccelll"
      let l:got =
       \ l:nb_dbgr_args == 0
       \ ? ""
       \ : a:000[0] == ""
       \ ? inputdialog("Enter arguments for debugging, if any: ", g:DBGRdebugArgs, l:cancelStr)
       \ : a:000[0]
      redraw!
      if l:got == l:cancelStr
         throw "CancelLaunch"
      endif
      let g:DBGRdebugArgs = l:got
      call s:LaunchDebugger("Perl", l:launchFileName, g:DBGRdebugArgs)
   catch /CouldntLaunchDaemon/
      echo "Couldn't launch daemon."
   catch /NoFileName/
      echo "Buffer has no filename, can't debug."
   catch /NoSuchFileYet/
      echo "Not a file on disk yet."
   catch /CancelLaunch/
      echo "Debugger launch cancelled."
   catch
      echo "Exception caught: " . v:exception
   endtry
endfunction

function! DBGRnext()
    call s:VddCmd("next", "Next")
endfunction

function! DBGRstepin()
   call s:VddCmd("stepin", "Step in")
endfunction

function! DBGRstepout()
   call s:VddCmd("stepout", "Step out")
endfunction

function! DBGRcont()
   call s:VddCmd("cont", "Continue")
endfunction

function! DBGRsetBreakPoint(fileName, bufNr, lynNr)
   if s:VddCmd("break:" . a:lynNr . ':' . a:fileName, "Set breakpoint")
      exe "let s:dbgr.bkpts." . s:BufLynId(a:bufNr, a:lynNr) . " = {" .
       \ "'bufNr' : " . a:bufNr . "," .
       \ "'lynNr' : " . a:lynNr . "," .
       \ "'cond' : 1,"
       \ "}"
      call s:MarkLine(1, 'bkpt', a:bufNr, a:lynNr)
   endif
endfunction

function! DBGRclearBreakPoint(fileName, bufNr, lynNr)
   if s:VddCmd("clear:" . a:lynNr . ':' . a:fileName, "Clear breakpoint")
      exe "unlet s:dbgr.bkpts." . s:BufLynId(a:bufNr, a:lynNr)
      call s:MarkLine(0, 'bkpt', a:bufNr, a:lynNr)
   endif
endfunction

function! DBGRclearAllBreakPoints()
   if s:VddCmd("clearAll", "Clear all breakpoints")
      call s:UnsetBkpts()
   endif
endfunction

function! DBGRprint(...)
   if a:0 > 0
      call s:VddCmd("print:" . a:1, "Print")
   endif
endfunction

function! DBGRcommand(...)
   if a:0 > 0
      call s:VddCmd("command:" . a:1, "Do command")
   endif
endfunction

function! DBGRrestart()
   if s:VddCmd("restart", "Restart the debugger")
      redraw!
   endif
endfunction

function! DBGRquit()
   if ! s:VddCmd("stop", "Stop")
      return
   endif
   call _VDsetInterface(0)
   call s:VDmapStartKey_DBGRstart()
   let s:dbgr.launched = 0
   call s:UnsetBkpts()

   set lazyredraw
      " Bring launch window and debug console to front.
   silent only
   exe "buffer " . s:dbgr.launchFile.bufNr
   wincmd n
   exe "buffer " . s:dbgr.consoleBufNr
   wincmd w

   for l:fileName in keys(s:dbgr.src)
      let l:info = s:dbgr.src[l:fileName]
      exe "buffer " . l:info.bufNr
      exe 'sign unplace ' . s:BufLynId(l:info.bufNr, 1)
      exe "setl " . (l:info.setNum ? "" : "no") . "number"
      exe "buffer " . s:dbgr.consoleBufNr
      if g:DBGRcloseInterm && ! l:info.hadBuf
         exe "bdelete " . l:info.bufNr
      endif
   endfor
   let s:dbgr.src = {}
   exe "buffer " . s:dbgr.launchFile.bufNr
   silent only
   let &l:number = s:dbgr.launchFile.setNum
   set nolazyredraw
   call s:PlaceSign('none', s:cursor.bufNr, 1)
   call s:VDsetToolBar(0)
      " Dispose of the console.
   exe s:dbgr.consoleBufNr . "bwipeout"
   let s:dbgr.consoleBufNr = 0
   call s:ClearCursor()
   redraw!
   echo "\rExited the debugger."
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
" Utility functions.

function! s:ErrorReport(errorId, msg)
   echo "Error " . a:errorId . ": " . a:msg
    \ . " Please report this to vimdebug at iijo dot org."
endfunction

   " Build a number identifying a given line in a given buffer.
function! s:BufLynId(bufNr, lynNr)
   return a:bufNr * 10000000 + a:lynNr
endfunction

function! s:ClearCursor()
   if s:cursor != {}
      call s:MarkLine(0, "cursor", s:cursor.bufNr, s:cursor.lynNr)
      " FIXME What about snapped?
   endif
   let s:cursor.bufNr = 0
   let s:cursor.lynNr = 0
   let s:cursor.snapped = 1
endfunction

function! s:UnsetBkpts()
   for l:bkpt in values(s:dbgr.bkpts)
      call s:MarkLine(
       \ 0,
       \ 'bkpt',
       \ l:bkpt.bufNr,
       \ l:bkpt.lynNr,
      \)
   endfor
   let s:dbgr.bkpts = {}
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

