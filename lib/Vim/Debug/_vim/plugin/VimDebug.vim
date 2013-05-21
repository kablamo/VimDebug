" (c) eric johnson
" email: vimDebug at iijo dot org
" http://iijo.org

" --------------------------------------------------------------------
" Check prerequisites.

if (!has('perl') || !has('signs'))
   echo "VimDebug requires +perl and +signs"
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

function! s:Initialize ()
   perl << EOT
         # Setting up 'lib' like this is useful during development.
      use Dir::Self;
      use lib __DIR__ . "/../../..";
         # Obtain protocol constant values directly from the Perl
         # module. This will allow us to use things like "s:k_eor" for
         # example in our Vim code.
      use Vim::Debug::Protocol;
      use Vim::Debug::Daemon;
      for my $method (qw<
         k_compilerError
         k_runtimeError
         k_dbgrReady
         k_appExited
         k_eor
         k_badCmd
         k_connect
         k_disconnect
         k_doneFile
      >) {
         VIM::DoCommand("let s:$method = '" . Vim::Debug::Protocol->$method . "'");
      }
         # Later perl snippets will use these variables.
      $DBGRsocket1 = 0;
      $DBGRsocket2 = 0;
      $EOM = Vim::Debug::Protocol->k_eom . "\r\n";
      $EOM_LEN = length $EOM;
      $PORT = Vim::Debug::Daemon->port;
EOT

      " Colors.
   hi currentLine term=reverse cterm=reverse gui=reverse
   hi breakPoint  term=NONE    cterm=NONE    gui=NONE
   hi empty       term=NONE    cterm=NONE    gui=NONE

      " Signs.
   sign define currentLine linehl=currentLine
   sign define breakPoint  linehl=breakPoint  text=>>
   sign define both        linehl=currentLine text=>>
   sign define empty       linehl=empty

      " Initialize globals to their default value, unless they already
      " have a value.
   for [l:var, l:dft_val] in items(s:cfg_globals)
      exec 
       \ "if ! exists('g:" . l:var . "') |" .
       \    "let " . l:var . " = '" . l:dft_val . "'| " .
       \ "endif"
   endfor

   " Script variables.

      " The string used to invoke the language's debugger.
   let s:incantation = ""

      " 0, the language's debugger is not running; 1, it is running.
   let s:dbgrIsRunning = 0

      " 0, a program is being debugged; 1, no program is being
      " debugged, or it has done running.
   let s:programDone = 1

      " Could eventually be some other debugger, but currently we
      " support only Perl.
   let s:debugger = "Perl"

   let s:consoleBufNr    = -99
   let s:bufNr           = 0
   let s:fileName        = ""
   let s:lineNumber      = 0
   let s:emptySigns      = []
   let s:breakPoints     = []
   let s:sessionId       = -1

   let s:interfaceSetting = 0

      " The user key bindings will be saved here if/when we launch
      " VimDebug. The entries of this list will be a bit different:
      " each one will be a two-element list of a key and of a
      " "saved-map" that will be provided by the 'savemap' vimscript.
   let s:userSavedkeys = []

      " Will be set to 1 (true) if the start key is defined
      " and we can map to it.
   let s:canMapStartKey = 0

   if s:cfg_startKey != "" && empty(maparg(s:cfg_startKey, "n"))
      let s:canMapStartKey = 1
   endif

      " Set up the start key and menus.
   call s:mapStartKey_DBGRstart()
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
      call s:mapStartKey_toggleKeyBindings()
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
   call s:mapStartKey_DBGRstart()

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

function! s:mapStartKey_DBGRstart ()
   if s:canMapStartKey
      exec "nmap " . s:cfg_startKey . " :call DBGRstart(\"\")<cr>"
   endif
endfunction

function! s:mapStartKey_toggleKeyBindings ()
   if s:canMapStartKey
      exec "nmap " . s:cfg_startKey . " :call _VDsetInterface(3)<cr>"
   endif
endfunction

" --------------------------------------------------------------------
" User commands.

command! -nargs=* VDstart      call DBGRstart(<f-args>)
command! -nargs=0 VDtoggleKeys call _VDsetInterface(3)

" --------------------------------------------------------------------
" Utility functions.

   " Returns 1 if everything is copacetic, 0 otherwise.
function! s:Copacetic()
   if s:dbgrIsRunning != 1
      echo "\rthe debugger is not running"
      return 0
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return 0
   endif
   return 1
endfunction

function! s:PlaceEmptySign()
   let l:id = s:CreateId(bufnr("%"), "1")
   if count(s:emptySigns, l:id) == 0
      let l:fileName = bufname("%")
      call add(s:emptySigns, l:id)
      exe "sign place " . l:id . " line=1 name=empty file=" . l:fileName
   endif
endfunction

function! s:UnplaceEmptySigns()
   let l:oldBufNr = bufnr("%")
   for l:id in s:emptySigns
      let l:bufNr = s:BufNrFromId(l:id)
      if bufexists(l:bufNr) != 0
         if bufnr("%") != l:bufNr
            exe "buffer " . l:bufNr
         endif
         exe "sign unplace " . l:id
         exe "buffer " . l:oldBufNr
      endif
   endfor
   let s:emptySigns = []
endfunction

function! s:UnplaceBreakPointSigns()
   let l:oldBufNr = bufnr("%")
   for l:id in s:breakPoints
      let l:bufNr = s:BufNrFromId(l:id)
      if bufexists(l:bufNr) != 0
         if bufnr("%") != l:bufNr
            exe "buffer " . l:bufNr
         endif
         exe "sign unplace " . l:id
         exe "buffer " . l:oldBufNr
      endif
   endfor
   let s:breakPoints = []
endfunction

function! s:SetNumber()
   if g:DBGRlineNumbers == 1
      set number
   endif
endfunction

function! s:SetNoNumber()
   if g:DBGRlineNumbers == 1
      set nonumber
   endif
endfunction

function! s:CreateId(bufNr, lineNumber)
   return a:bufNr * 10000000 + a:lineNumber
endfunction

function! s:BufNrFromId(id)
   return a:id / 10000000
endfunction

function! s:LineNrFromId(id)
   return a:id % 10000000
endfunction

function! s:Incantation(dbgr_args_list)
   try
      let s:bufNr       = bufnr("%")
      let s:fileName    = bufname("%")
      if s:fileName == ""
         throw "NoFileToDebug"
      endif
      let l:nb_dbgr_args = len(a:dbgr_args_list)
      let g:DBGRdebugArgs =
       \ l:nb_dbgr_args == 0
       \ ? ""
       \ : l:nb_dbgr_args == 1 && a:dbgr_args_list[0] == ""
       \ ? inputdialog("Enter arguments for debugging, if any: ", g:DBGRdebugArgs)
       \ : join(a:dbgr_args_list)
      let s:incantation = "perl -Ilib -d " . s:fileName
      if g:DBGRdebugArgs != ""
         let s:incantation .= " " . g:DBGRdebugArgs
      endif
   catch /NoFileToDebug/
      echo "No file to debug."
      throw "AbortLaunch"
   catch
      echo "Exception caught: " . v:exception
      throw "AbortLaunch"
   endtry
endfunction

function! s:HandleCmdResult(...)
   let l:cmdResult  = split(s:SocketRead(), s:k_eor, 1)
   let [l:status, l:lineNumber, l:fileName, l:value, l:output] = l:cmdResult

   if l:status == s:k_dbgrReady
      call s:ConsolePrint(l:output)
      if len(l:lineNumber) > 0
         call s:CurrentLineMagic(l:lineNumber, l:fileName)
      endif

   elseif l:status == s:k_appExited
      call s:ConsolePrint(l:output)
      call s:HandleProgramTermination()
      redraw! | echo "The application being debugged terminated."

   elseif l:status == s:k_compilerError
      call s:ConsolePrint(l:output)
      call s:HandleProgramTermination()
      redraw! | echo "The program did not compile."

   elseif l:status == s:k_runtimeError
      call s:ConsolePrint(l:output)
      call s:HandleProgramTermination()
      redraw! | echo "There was a runtime error."

   elseif l:status == s:k_connect
      let s:sessionId = l:value

   elseif l:status == s:k_disconnect
      echo "disconnected"

   else
      echo " error:001. Something bad happened. Please report this to vimdebug at iijo dot org"
      echo got
   endif

   return
endfunction

function! s:HandleCmdResult2(...)
   let l:foo = s:SocketRead2()
endfunction

" - jumps to the lineNumber in the file, fileName
" - highlights the current line
" - returns nothing
function! s:CurrentLineMagic(lineNumber, fileName)

   let l:lineNumber = a:lineNumber
   let l:fileName   = a:fileName
   let l:fileName   = s:JumpToLine(l:lineNumber, l:fileName)

   " if no signs placed in this file, place an invisible one on line 1.
   " otherwise, the code will shift left when the old currentline sign is
   " unplaced and then shift right again when the new currentline sign is
   " placed.  and thats really annoying for the user.
   call s:PlaceEmptySign()
   call s:UnplaceTheLastCurrentLineSign()                " unplace the old sign
   call s:PlaceCurrentLineSign(l:lineNumber, l:fileName) " place the new sign
   call s:SetNumber()
   "z. " scroll page so that this line is in the middle

   " set script variables for next time
   let s:lineNumber = l:lineNumber
   let s:fileName   = l:fileName

   return
endfunction

" the fileName may have been changed if we stepped into a library or some
" other piece of code in an another file.  load the new file if thats
" necessary and then jump to lineNumber
"
" returns a fileName.
function! s:JumpToLine(lineNumber, fileName)
   let l:fileName = a:fileName

   " no buffer with this file has been loaded
   if !bufexists(bufname(l:fileName))
      exe ":e! " . l:fileName
   endif

   let l:winNr = bufwinnr(bufnr(l:fileName))
   if l:winNr != -1
      exe l:winNr . "wincmd w"
   endif

   " make a:fileName the current buffer
   if bufname(l:fileName) != bufname("%")
      exe ":buffer " . bufnr(l:fileName)
   endif

   " jump to line
   exe ":" . a:lineNumber
   normal z.
   if foldlevel(a:lineNumber) != 0
      normal zo
   endif

   return bufname(l:fileName)
endfunction

function! s:UnplaceTheLastCurrentLineSign()
   let l:lastId = s:CreateId(s:bufNr, s:lineNumber)
   exe 'sign unplace ' . l:lastId
   if count(s:breakPoints, l:lastId) == 1
      exe "sign place " . l:lastId . " line=" . s:lineNumber . " name=breakPoint file=" . s:fileName
   endif
endfunction

function! s:PlaceCurrentLineSign(lineNumber, fileName)
   let l:bufNr = bufnr(a:fileName)
   let s:bufNr = l:bufNr
   let l:id    = s:CreateId(l:bufNr, a:lineNumber)

   if count(s:breakPoints, l:id) == 1
      exe "sign place " . l:id .
        \ " line=" . a:lineNumber . " name=both file=" . a:fileName
   else
      exe "sign place " . l:id .
        \ " line=" . a:lineNumber . " name=currentLine file=" . a:fileName
   endif
endfunction

function! s:HandleProgramTermination()
   call s:UnplaceTheLastCurrentLineSign()
   let s:lineNumber  = 0
   let s:bufNr       = 0
   let s:programDone = 1
endfunction

" --------------------------------------------------------------------
" Debugger console functions.

function! DBGRopenConsole()
   if g:DBGRshowConsole == 0
      return 0
   endif
   new "debugger console"
   let s:consoleBufNr = bufnr('%')
   exe "resize " . g:DBGRconsoleHeight
   exe "sign place 9999 line=1 name=empty buffer=" . s:consoleBufNr
   call s:SetNumber()
   set buftype=nofile
   wincmd p
endfunction

function! DBGRcloseConsole()
   if g:DBGRshowConsole == 0
      return 0
   endif
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      return
   endif
   exe l:consoleWinNr . "wincmd w"
   q
endfunction

function! s:ConsolePrint(msg)
   if g:DBGRshowConsole == 0
      return 0
   endif
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      "call confirm(a:msg, "&Ok")
      call DBGRopenConsole()
      let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   endif
   silent exe l:consoleWinNr . "wincmd w"
   let l:oldValue = @x
   let @x = a:msg
   silent exe 'normal G$"xp'
   let @x = l:oldValue
   normal G
   wincmd p
endfunction

" --------------------------------------------------------------------
" Socket functions.

function! s:StartVdd()
   if !executable('vdd')
      throw "MissingVdd"
   endif
   exec "silent :! vdd &"
endfunction

function! s:Handshake()
    let l:msg  = "start:" . s:sessionId .
               \      ":" . s:debugger .
               \      ":" . s:incantation
    call s:SocketWrite(l:msg)
endfunction

function! s:SocketConnect()
   perl << EOF
      use IO::Socket;
      foreach my $i (0..9) {
         $DBGRsocket1 = IO::Socket::INET->new(
            Proto    => "tcp",
            PeerAddr => "localhost",
            PeerPort => $PORT,
         );
         return if defined $DBGRsocket1;
         sleep 1;
      }
      my $msg = "cannot connect to port $PORT at localhost";
      VIM::Msg($msg);
      VIM::DoCommand("throw '${msg}'");
EOF
endfunction

function! s:SocketConnect2()
   perl << EOF
      use IO::Socket;
      foreach my $i (0..9) {
         $DBGRsocket2 = IO::Socket::INET->new(
            Proto    => "tcp",
            PeerAddr => "localhost",
            PeerPort => $PORT,
         );
         return if defined $DBGRsocket2;
         sleep 1;
      }
      my $msg = "cannot connect to port $PORT at localhost";
      VIM::Msg($msg);
      VIM::DoCommand("throw '${msg}'");
EOF
endfunction

function! s:SocketRead()
   try
      " yeah this is a very inefficient but non blocking loop.
      " vdd signals that its done sending a msg when it touches the file.
      " while VimDebug thinks, the user can cancel their operation.
      while !filereadable(s:k_doneFile)
      endwhile
   catch /Vim:Interrupt/
      echom "action cancelled"
      call s:SocketWrite2('stop:' . s:sessionId)  " disconnect
      call s:HandleCmdResult2()                   " handle disconnect
      call s:SocketConnect2()                     " reconnect
      call s:HandleCmdResult2()                   " handle reconnect
   endtry

   perl << EOF
      my $data = '';
      $data .= <$DBGRsocket1> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data .= <$DBGRsocket1> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data = substr($data, 0, -1 * $EOM_LEN); # chop EOM
      $data =~ s|'|''|g; # escape single quotes '
      VIM::DoCommand("call delete(s:k_doneFile)");
      VIM::DoCommand("return '" . $data . "'");
EOF
endfunction

function! s:SocketRead2()
   try
      " yeah this is a very inefficient but non blocking loop.
      " vdd signals that its done sending a msg when it touches the file.
      " while VimDebug thinks, the user can cancel their operation.
      while !filereadable(s:k_doneFile)
      endwhile
   endtry

   perl << EOF
      my $data = '';
      $data .= <$DBGRsocket2> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data .= <$DBGRsocket2> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data = substr($data, 0, -1 * $EOM_LEN); # chop EOM
      $data =~ s|'|''|g; # escape single quotes '
      VIM::DoCommand("call delete(s:k_doneFile)");
      VIM::DoCommand("return '" . $data . "'");
EOF
endfunction

function! s:SocketWrite(data)
   perl print $DBGRsocket1 VIM::Eval('a:data') . "\n";
endfunction

function! s:SocketWrite2(data)
   perl print $DBGRsocket2 VIM::Eval('a:data') . "\n";
endfunction

" --------------------------------------------------------------------
" Initialize everything.

call s:Initialize()

