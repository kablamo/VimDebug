" (c) eric johnson
" email: vimDebug at iijo dot org
" http://iijo.org


" key bindings
map <F12>         :DBGRstart<CR>
map <Leader><F12> :DBGRstart   
map <F7>          :DBGRstep<CR>
map <F8>          :DBGRnext<CR>
map <F9>          :DBGRcont<CR>                   " continue
map <Leader>b     :DBGRsetBreakPoint<CR>
map <Leader>c     :DBGRclearBreakPoint<CR>
map <Leader>ca    :DBGRclearAllBreakPoints<CR>
map <Leader>v/    :DBGRprint 
map <Leader>v     :DBGRprintExpand expand("<cWORD>")<CR> " value under cursor
map <Leader>/     :DBGRcommand 
map <F10>         :DBGRrestart<CR>
map <F11>         :DBGRquit<CR>

" commands
command! -nargs=* DBGRstart               call DBGRstart("<args>")
command! -nargs=0 DBGRstep                call DBGRstep()
command! -nargs=0 DBGRnext                call DBGRnext()
command! -nargs=0 DBGRcont                call DBGRcont()
command! -nargs=0 DBGRsetBreakPoint       call DBGRsetBreakPoint()
command! -nargs=0 DBGRclearBreakPoint     call DBGRclearBreakPoint()
command! -nargs=0 DBGRclearAllBreakPoints call DBGRclearAllBreakPoints()
command! -nargs=1 DBGRprintExpand         call DBGRprint(<args>)
command! -nargs=1 DBGRcommand             call DBGRcommand("<args>")
command! -nargs=0 DBGRrestart             call DBGRrestart()
command! -nargs=0 DBGRquit                call DBGRquit(0)

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

" script constants
let s:LINE_INFO       = "vimDebug:"
let s:COMPILER_ERROR  = "compiler error"
let s:RUNTIME_ERROR   = "runtime error"
let s:APP_EXITED      = "application exited"
let s:DBGR_READY      = "debugger ready"

" script variables
let s:sessionId       = getpid()
let s:dbgrIsRunning   = 0
let s:ctl_vddFIFOvim  = ".ctl_vddFIFOvim." . s:sessionId
let s:ctl_vimFIFOvdd  = ".ctl_vimFIFOvdd." . s:sessionId
let s:dbg_vddFIFOvim  = ".dbg_vddFIFOvim." . s:sessionId
let s:consoleInited   = 0
let s:consoleBufNr    = -99
let s:consoleFile     = "/tmp/vdd." . $USER . "." . s:sessionId . ".dbgr"
let s:incantation     = ""
let s:lineNumber      = 0
let s:fileName        = ""
let s:bufNr           = 0
let s:programDone     = 0

" note that these aren't really arrays.  its a string.  different values are
" separated by s:sep.  manipulation of the 'array' is done with an array
" library: http://vim.sourceforge.net/script.php?script_id=171
let s:emptySignArray  = ""                           " array
let s:breakPointArray = ""                           " array
let s:sep             = "-"                          " array separator


" debugger functions
function! DBGRstart(...)
   if s:dbgrIsRunning
      call s:ConsoleSetFocus()
      echo "\rthe debugger is already running"
      return
   endif

   if has("autocmd")
      autocmd VimLeavePre * call DBGRquit(1)
   endif

   try
      let s:incantation = s:Incantation(a:1)
   catch "can't debug file type"
      return
   endtry

   call s:ConsoleInit()
   exe "silent :! " . s:incantation . '> ' . s:consoleFile . ' 2>&1 &'
   sleep 1
   if getfsize(s:consoleFile) > 0
      echo "There was an error. See " . s:consoleFile . "."
      return
   endif

   " do after system() so nongui vim doesn't show a blank screen
   echo "\rstarting the debugger..."

   " loop until vdd says the debugger is done loading
   while !filewritable(s:ctl_vddFIFOvim)
      " this works in gvim but is misleading on the console
      " echo "\rwaiting for debugger to start (hit <C-c> to give up)..."
      continue
   endwhile

   if g:DBGRshowConsole == 1
      call s:ConsoleSetFocus()
   endif

   redraw!
   call s:HandleCmdResult("started the debugger")
   let s:dbgrIsRunning = 1
endfunction
function! DBGRnext()
   if !s:Copacetic()
      return
   endif
   echo "\rnext..."
   call system('echo "next" >> ' . s:ctl_vimFIFOvdd)
   call s:HandleCmdResult()
endfunction
function! DBGRstep()
   if !s:Copacetic()
      return
   endif
   echo "\rstep..."
   call system('echo "step" >> ' . s:ctl_vimFIFOvdd)
   call s:HandleCmdResult()
endfunction
function! DBGRcont()
   if !s:Copacetic()
      return
   endif
   echo "\rcontinue..."
   call system('echo "cont" >> ' . s:ctl_vimFIFOvdd)
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


   " check if a breakPoint sign is already placed
   if MvContainsElement(s:breakPointArray, s:sep, l:id) == 1
      redraw! | echo "\rbreakpoint already set"
      return
   endif


   " tell vdd about the new break point
   silent exe "redir >> " . s:ctl_vimFIFOvdd . '| echon "break:' . l:currLineNr . ':' . l:currFileName . '" | redir END'


   let s:breakPointArray = MvAddElement(s:breakPointArray, s:sep, l:id)

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


   " check if a breakPoint sign has really been placed here
   if MvContainsElement(s:breakPointArray, s:sep, l:id) == 0
      redraw! | echo "\rno breakpoint set here"
      return
   endif


   " tell vdd about the deleted break point
   silent exe "redir >> " . s:ctl_vimFIFOvdd . '| echon "clear:' . l:currLineNr . ':' . l:currFileName . '" | redir END'


   let s:breakPointArray = MvRemoveElement(s:breakPointArray, s:sep, l:id)
   exe "sign unplace " . l:id

   " place a currentLine sign if this is the currentLine
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

   silent exe "redir >> " . s:ctl_vimFIFOvdd . '| echon "clearAll" | redir END'

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
      call system("echo 'printExpression:" . a:1 . "' >> " . s:ctl_vimFIFOvdd)
      call s:HandleCmdResult()
   endif
endfunction
function! DBGRcommand(...)
   if !s:Copacetic()
      return
   endif
   echo ""
   if a:0 > 0
      call system( "echo 'command:" . a:1 . "' >> " . s:ctl_vimFIFOvdd )
      call s:HandleCmdResult()
   endif
endfunction
function! DBGRrestart()
   if ! s:dbgrIsRunning
      echo "\rthe debugger is not running"
      return
   endif
   call system( 'echo "restart" >> ' . s:ctl_vimFIFOvdd )
   " do after the system() call so that nongui vim doesn't show a blank screen
   echo "\rrestarting..."
   call s:UnplaceTheLastCurrentLineSign()
   redraw!
   call s:HandleCmdResult("restarted")
   let s:programDone = 0
endfunction
function! DBGRquit(silent)
   if ! s:dbgrIsRunning
      if ! a:silent
         echo "\rthe debugger is not running"
      endif
      return
   endif

   " unplace all signs that were set in this debugging session
   call s:UnplaceBreakPointSigns()
   call s:UnplaceEmptySigns()
   call s:UnplaceTheLastCurrentLineSign()
   call s:SetNoLineNumbers()
   call s:ConsoleClose()

   call system('echo "quit" >> ' . s:ctl_vimFIFOvdd)


   " reinitialize script variables
   let s:lineNumber      = 0
   let s:fileName        = ""
   let s:bufNr           = 0
   let s:programDone     = 0
   let s:sep             = "-"

   let s:dbgrIsRunning = 0
   redraw! | echo "\rexited the debugger"

endfunction


" utility functions

" returns 1 if everything is copacetic
" returns 0 if things are not copacetic
function! s:Copacetic()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return 0
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return 0
   endif
   return 1
endfunction
function! s:PlaceEmptySign()
   let l:id       = s:CreateId(bufnr("%"), "1")
   let l:fileName = bufname("%")
   if !MvContainsElement(s:emptySignArray, s:sep, l:id) == 1
      let s:emptySignArray = MvAddElement(s:emptySignArray, s:sep, l:id)
      exe "sign place " . l:id . " line=1 name=empty file=" . l:fileName
   endif
endfunction
function! s:UnplaceEmptySigns()

   let l:oldBufNr = bufnr("%")
   call MvIterCreate(s:emptySignArray, s:sep, "VimDebugIteratorE")

   while MvIterHasNext("VimDebugIteratorE")
      let l:id         = MvIterNext("VimDebugIteratorE")
      let l:bufNr      = s:CalculateBufNrFromId(l:id)
      if bufexists(l:bufNr) != 0
         if bufnr("%") != l:bufNr
            exe "buffer " . l:bufNr
         endif
         exe "sign unplace " . l:id
         exe "buffer " . l:oldBufNr
      endif
   endwhile

   call MvIterDestroy("VimDebugIteratorE")

   let s:emptySignArray  = ""

endfunction
function! s:UnplaceBreakPointSigns()

   let l:oldBufNr = bufnr("%")
   call MvIterCreate(s:breakPointArray, s:sep, "VimDebugIteratorB")

   while MvIterHasNext("VimDebugIteratorB")
      let l:id         = MvIterNext("VimDebugIteratorB")
      let l:bufNr      = s:CalculateBufNrFromId(l:id)
      if bufexists(l:bufNr) != 0
         if bufnr("%") != l:bufNr
            exe "buffer " . l:bufNr
         endif
         exe "sign unplace " . l:id
         exe "buffer " . l:oldBufNr
      endif
   endwhile

   call MvIterDestroy("VimDebugIteratorB")

   let s:breakPointArray = ""

endfunction
function! s:SetLineNumbers()
   if g:DBGRlineNumbers == 1
      set number
   endif
endfunction
function! s:SetNoLineNumbers()
   if g:DBGRlineNumbers == 1
      set nonumber
   endif
endfunction
function! s:CreateId(bufNr, lineNumber)
   return a:bufNr * 10000000 + a:lineNumber
endfunction
function! s:CalculateBufNrFromId(id)
   return a:id / 10000000
endfunction
function! s:CalculateLineNumberFromId(id)
   return a:id % 10000000
endfunction
function! s:AutoIncantation(...)
   if     a:1 == "Perl"
      return "perl -Ilib -d '" . s:fileName . "'"
   elseif a:1 == "Gdb"
      return "gdb '" . s:fileName . "' -f"
   elseif a:1 == "Python"
      return "pdb '" . s:fileName . "'"
   elseif a:1 == "Ruby"
      return "ruby -rdebug '" . s:fileName . "'"
   endif
endfunction
function! s:Incantation(...)
   let s:bufNr          = bufnr("%")
   let s:fileName       = bufname("%")
   let l:debugger       = s:DbgrName(s:fileName)
   let l:vddIncantation =
    \ "vdd " . s:sessionId . " " . l:debugger . " " . s:AutoIncantation(l:debugger)

   return l:vddIncantation . (a:0 == 0 ? '' : (" " . join(a:000, " ")))
endfunction
function! s:DbgrName(fileName)
   let l:fileExtension = fnamemodify(a:fileName, ':e')

   " consult file extension and filetype
   if     &l:filetype == "perl"   || l:fileExtension == "pl"
      return "Perl"
   elseif &l:filetype == "c"      || l:fileExtension == "c"   ||
        \ &l:filetype == "cpp"    || l:fileExtension == "cpp"
      return "Gdb"
   elseif &l:filetype == "python" || l:fileExtension == "py"
      return "Python"
   elseif &l:filetype == "ruby"   || l:fileExtension == "r"
      return "Ruby"
   else
      echo "\rthere is no debugger associated with this file type"
      throw "can't debug file type"
   endif
endfunction


function! s:HandleCmdResult(...)

   " get command results from vdd
   let l:cmdResult = system('cat ' . s:ctl_vddFIFOvim)

   if match(l:cmdResult, '^' . s:LINE_INFO . '\d\+:.*$') != -1
      let l:cmdResult = substitute(l:cmdResult, '^' . s:LINE_INFO, "", "")
      if a:0 == 0 || match(a:1, 'breakpoint') == -1
         call s:CurrentLineMagic(l:cmdResult)
      endif
      if a:0 > 0
         echo "\r" . a:1 . "                    "
      endif

   elseif l:cmdResult == s:APP_EXITED
      call s:HandleProgramTermination()
      redraw! | echo "\rthe application being debugged terminated"

   elseif match(l:cmdResult, '^' . s:COMPILER_ERROR) != -1
      call s:ConsolePrint(substitute(l:cmdResult, '^' . s:COMPILER_ERROR, "", ""))

   elseif match(l:cmdResult, '^' . s:RUNTIME_ERROR) != -1
      call s:ConsolePrint(substitute(l:cmdResult, '^' . s:RUNTIME_ERROR, "", ""))

   elseif l:cmdResult == s:DBGR_READY
      if a:0 > 0
         echo "\r" . a:1 . "                    "
      endif

   else
      " i have to do this because of a vim redraw bug which clears the
      " messages i echo after returning.  grumble grumble.
      if match(l:cmdResult, "\n") != -1
         redraw!
      endif
      call s:ConsolePrint(l:cmdResult)

   endif

   " print debugger output obtained from vdd
   let l:dbgOut = system('cat ' . s:dbg_vddFIFOvim)
   call s:ConsolePrint(l:dbgOut)

   return
endfunction
" - gets lineNumber / fileName from the debugger
" - jumps to the lineNumber in the file, fileName
" - highlights the current line
"
" parameters
"    lineInfo: a string with the format 'lineNumber:fileName'
"
" returns nothing
function! s:CurrentLineMagic(lineInfo)

   let l:lineNumber = substitute(a:lineInfo, "\:.*$", "", "")
   let l:fileName   = substitute(a:lineInfo, "^\\d\\+\:", "", "")
   let l:fileName   = s:JumpToLine(l:lineNumber, l:fileName)

   " if there haven't been any signs placed in this file yet, place one the
   " user can't see on line 1 just to shift everything over.  otherwise, the
   " code will shift left when the old currentline sign is unplaced and then
   " shift right again when the new currentline sign is placed.  and thats
   " really annoying for the user.
   call s:PlaceEmptySign()
   call s:UnplaceTheLastCurrentLineSign()                " unplace the old sign
   call s:PlaceCurrentLineSign(l:lineNumber, l:fileName) " place the new sign
   call s:SetLineNumbers()
   "z. " scroll page so that this line is in the middle

   " set script variables for next time
   let s:lineNumber = l:lineNumber
   let s:fileName   = l:fileName

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

   " check if there was a break point at l:lastId
   if MvContainsElement(s:breakPointArray, s:sep, l:lastId) == 1
      exe "sign place " . l:lastId . " line=" . s:lineNumber . " name=breakPoint file=" . s:fileName
   endif

endfunction
function! s:PlaceCurrentLineSign(lineNumber, fileName)

   " place the new currentline sign
   let l:bufNr = bufnr(a:fileName)
   let l:id    = s:CreateId(l:bufNr, a:lineNumber)

   if MvContainsElement(s:breakPointArray, s:sep, l:id) == 1
      exe "sign place " . l:id .
        \ " line=" . a:lineNumber . " name=both file=" . a:fileName
   else
      exe "sign place " . l:id .
        \ " line=" . a:lineNumber . " name=currentLine file=" . a:fileName
   endif

   " set script variable for next time
   let s:bufNr = l:bufNr

endfunction

function! s:HandleProgramTermination()
   call s:UnplaceTheLastCurrentLineSign()
   let s:lineNumber  = 0
   let s:bufNr       = 0
   let s:programDone = 1
endfunction

" debugger console functions
function! s:ConsoleInit()
   if s:consoleInited
      return
   endif
   new "debugger console"
   let s:consoleBufNr = bufnr('%')
   exe "silent w " . s:consoleFile
   exe "sign place 9999 line=1 name=empty buffer=" . s:consoleBufNr
   call s:SetLineNumbers()
   hide
   let s:consoleInited = 1
endfunction
function! s:ConsoleSetFocus()
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      call s:ConsoleRefresh()
   endif
   exe l:consoleWinNr . "wincmd w"
endfunction
function! s:ConsoleRefresh()
   silent wincmd o
   if bufnr("%") != s:consoleBufNr
      exe "silent e #" . s:consoleBufNr
   endif
   silent exe g:DBGRconsoleHeight . "wincmd s"
   normal G
   wincmd t
   exe "silent e #" . s:bufNr
endfunction
function! s:ConsolePrint(msg)
   call s:ConsoleSetFocus()
   let l:oldValue = @x
   let @x = a:msg
   silent exe 'normal G$"xp'
   let @x = l:oldValue
   normal G
   setl nomodified
   wincmd p
endfunction
function! s:ConsoleClose()
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      try
         exe ":e " . s:consoleBufNr
      catch
         return
      endtry
   else
      exe l:consoleWinNr . "wincmd w"
   endif
   exe "bdelete! " . s:consoleBufNr
   call delete(s:consoleFile)
endfunction

