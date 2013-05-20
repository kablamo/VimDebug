" (c) eric johnson
" email: vimDebug at iijo dot org
" http://iijo.org

" Check prerequisites.

if (!has('perl') || !has('signs'))
   echo "VimDebug requires +perl and +signs"
   finish
endif

   " The VimDebug start key. If you unset it, VimDebug won't load.
let s:StartKey = "<F12>"
if s:StartKey == ""
   echo "No start key defined, so you can't use VimDebug."
   finish
endif

   " Make sure the start key is available.
try
   exec "nmap <unique> " . s:StartKey . " :call VDstart(\"\")<cr>"
catch
   echo v:exception
   echo "Can't use VimDebug, its start key " . s:StartKey . " is already mapped."
   exec "map " . s:StartKey
   finish
endtry

   " Define the debugger key bindings. Be careful if you change these
   " values or s:StartKey. Each entry of the list is a two-element
   " list defining a key and its corresponding mapping.
let s:dbgr_keys = [
  \ ["<F11>",      ":DBGRquit<cr>"],
  \ ["<F10>",      ":DBGRrestart<cr>"],
  \ ["<F9>",       ":DBGRcont<cr>"],
  \ ["<F8>",       ":DBGRnext<cr>"],
  \ ["<F7>",       ":DBGRstep<cr>"],
  \ ["<F6>",       ":DBGRstepout<cr>"],
  \ ["<Leader>b",  ":DBGRsetBreakPoint<cr>"],
  \ ["<Leader>c",  ":DBGRclearBreakPoint<cr>"],
  \ ["<Leader>ca", ":DBGRclearAllBreakPoints<cr>"],
  \ ["<Leader>x/", ":DBGRprint<space>"],
  \ ["<Leader>x",  ":DBGRprintExpand expand(\"<cword>\")<cr> \""],
  \ ["<Leader>/",  ":DBGRcommand<space>"],
\]
   " The user keys will be saved here if/when we launch VimDebug. The
   " entries of this list will be a bit different: each one will be a
   " two-element list of a key and of a "saved-map" that will be
   " provided by the 'savemap' vimscript.
let s:user_savedkeys    = []

" Miscellaneous settings.

" colors
hi currentLine term=reverse cterm=reverse gui=reverse
hi breakPoint  term=NONE    cterm=NONE    gui=NONE
hi empty       term=NONE    cterm=NONE    gui=NONE

" signs
sign define currentLine linehl=currentLine
sign define breakPoint  linehl=breakPoint  text=>>
sign define both        linehl=currentLine text=>>
sign define empty       linehl=empty

" global variables
let g:DBGRconsoleHeight   = 7
let g:DBGRlineNumbers     = 1
let g:DBGRshowConsole     = 1

let s:PORT            = 6543
let s:HOST            = "localhost"
let s:DONE_FILE       = ".vdd.done"

" script variables
let s:incantation     = ""
let s:dbgrIsRunning   = 0    " 0: !running, 1: running, 2: starting
let s:debugger        = "Perl"
let s:lineNumber      = 0
let s:fileName        = ""
let s:bufNr           = 0
let s:programDone     = 0
let s:consoleBufNr    = -99
let s:emptySigns      = []
let s:breakPoints     = []
let s:return          = 0
let s:sessionId       = -1

" Perl setup.

perl << EOT
      # Setting up 'lib' like this is useful during development.
   use Dir::Self;
   use lib __DIR__ . "/../../..";
      # Obtain protocol constant values directly from the Perl
      # module. This will allow us to use things like "s:k_eor" for
      # example in our Vim code.
   use Vim::Debug::Protocol;
   for my $method (qw<
      k_compilerError
      k_runtimeError
      k_dbgrReady
      k_appExited
      k_eor
      k_badCmd
      k_connect
      k_disconnect
   >) {
      VIM::DoCommand("let s:$method = '" . Vim::Debug::Protocol->$method . "'");
   }
      # Later perl snippets will use these variables.
   $DBGRsocket1 = 0;
   $DBGRsocket2 = 0;
   $EOM = Vim::Debug::Protocol->k_eom . "\r\n";
   $EOM_LEN = length $EOM;
EOT

" VimDebug

   " We keep track of two sets of key bindings: 0, the user's key
   " bindings as they stand before we install VimDebug's, and 1,
   " VimDebug's own, when the debugger is running.
let s:current_keys = 0

   " Start the debugger if it's not already running, or toggle the
   " keyboard. If argument is empty string, prompt for arguments.
function! VDstart(...)
   if ! s:dbgrIsRunning
      try
         call _VDinit(a:000)
         call _VDsetKeys(1)
      catch /NotStarted/
         let s:dbgrIsRunning = 0
      endtry
   else
      call _VDsetKeys(2)
   endif
endfunction

function! _VDinit(dbgr_args_list)
   try
      call s:Incantation(a:dbgr_args_list)
      let s:dbgrIsRunning = 2
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
      let s:dbgrIsRunning = 1
   catch /AbortLaunch/
      echo "Debugger launch aborted."
      throw "NotStarted"
   catch /MissingVdd/
      echo "vdd is not in your PATH. Something went wrong with your VimDebug install."
      throw "NotStarted"
   catch /.*/
      echo "Unexpected error: " . v:exception
      throw "NotStarted"
   endtry
endfunction

   " Request keys 1 for VimDebug's key bindings, or 0 for the user's, or 2
   " to toggle between the two.
function! _VDsetKeys (req_keys)
   if ! s:dbgrIsRunning
      return
   endif
   if a:req_keys == 2
         " Toggle between 0 and 1.
      let want_keys = 1 - s:current_keys
   else
      let want_keys = a:req_keys
   endif
   if want_keys == 1
      let s:user_savedkeys = []
      for key_map in s:dbgr_keys
         let key = key_map[0]
         let map = key_map[1]
         call add(s:user_savedkeys, [key, savemap#save_map("n", key)])
         exec "nmap " . key . " " . map
      endfor
      let s:current_keys = 1
      echo "VimDebug keys are active."
   else
      for key_savedmap in s:user_savedkeys
         let key = key_savedmap[0]
         let saved_map = key_savedmap[1]
         if empty(saved_map['__map_info'][0]['normal'])
            exec "unmap " . key
         else
            call saved_map.restore()
         endif
      endfor
      let s:current_keys = 0
      echo "User keys are active."
   endif
endfunction

" Debugger functions.

command! -nargs=0 DBGRstepout             call DBGRstepout()
command! -nargs=0 DBGRstep                call DBGRstep()
command! -nargs=0 DBGRnext                call DBGRnext()
command! -nargs=0 DBGRcont                call DBGRcont()
command! -nargs=0 DBGRsetBreakPoint       call DBGRsetBreakPoint()
command! -nargs=0 DBGRclearBreakPoint     call DBGRclearBreakPoint()
command! -nargs=0 DBGRclearAllBreakPoints call DBGRclearAllBreakPoints()
command! -nargs=1 DBGRprintExpand         call DBGRprint("<args>")
command! -nargs=1 DBGRcommand             call DBGRcommand("<args>")
command! -nargs=0 DBGRrestart             call DBGRrestart()
command! -nargs=0 DBGRquit                call DBGRquit()

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
   call _VDsetKeys(0)

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
   let s:programDone     = 0

   let s:dbgrIsRunning = 0
   redraw! | echo "\rexited the debugger"

   " must do this last
   call DBGRcloseConsole()
endfunction

" Utility functions.

" returns 1 if everything is copacetic
" returns 0 if things are not copacetic
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
      let nb_dbgr_args = len(a:dbgr_args_list)
      if nb_dbgr_args == 0
         let dbgr_args = ""
      elseif nb_dbgr_args == 1 && a:dbgr_args_list[0] == ""
         let dbgr_args = input("Enter arguments if any: ")
      else
         let dbgr_args = join(a:dbgr_args_list)
      endif
         " Some day, we may do more than just Perl.
      let s:incantation = "perl -Ilib -d " . s:fileName
      if dbgr_args != ""
         let s:incantation .= " " . dbgr_args
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
            PeerPort => "6543",
         );
         return if defined $DBGRsocket1;
         sleep 1;
      }
      my $msg = "cannot connect to port 6543 at localhost";
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
            PeerPort => "6543",
         );
         return if defined $DBGRsocket2;
         sleep 1;
      }
      my $msg = "cannot connect to port 6543 at localhost";
      VIM::Msg($msg);
      VIM::DoCommand("throw '${msg}'");
EOF
endfunction

function! s:SocketRead()
   try 
      " yeah this is a very inefficient but non blocking loop.
      " vdd signals that its done sending a msg when it touches the file.
      " while VimDebug thinks, the user can cancel their operation.
      while !filereadable(s:DONE_FILE)
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
      VIM::DoCommand("call delete(s:DONE_FILE)");
      VIM::DoCommand("return '" . $data . "'"); 
EOF
endfunction

function! s:SocketRead2()
   try 
      " yeah this is a very inefficient but non blocking loop.
      " vdd signals that its done sending a msg when it touches the file.
      " while VimDebug thinks, the user can cancel their operation.
      while !filereadable(s:DONE_FILE)
      endwhile
   endtry
   
   perl << EOF
      my $data = '';
      $data .= <$DBGRsocket2> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data .= <$DBGRsocket2> until substr($data, -1 * $EOM_LEN) eq $EOM;
      $data = substr($data, 0, -1 * $EOM_LEN); # chop EOM
      $data =~ s|'|''|g; # escape single quotes '
      VIM::DoCommand("call delete(s:DONE_FILE)");
      VIM::DoCommand("return '" . $data . "'"); 
EOF
endfunction

function! s:SocketWrite(data)
   perl print $DBGRsocket1 VIM::Eval('a:data') . "\n";
endfunction

function! s:SocketWrite2(data)
   perl print $DBGRsocket2 VIM::Eval('a:data') . "\n";
endfunction

