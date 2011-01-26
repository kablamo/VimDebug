" (c) eric johnson
" email: vimDebug at iijo dot org
" http://iijo.org


" key bindings
map <F12>      :DBGRstart<CR>
map <Leader>s/ :DBGRstart 

map <F7>       :call DBGRstep()<CR>
map <F8>       :call DBGRnext()<CR>
map <F9>       :call DBGRcont()<CR>                   " continue

map <Leader>b  :call DBGRsetBreakPoint()<CR>
map <Leader>c  :call DBGRclearBreakPoint()<CR>
map <Leader>ca :call DBGRclearAllBreakPoints()<CR>

map <Leader>v/ :DBGRprint 
map <Leader>v  :DBGRprintExpand expand("<cWORD>")<CR> " print value under the cursor

map <Leader>/  :DBGRcommand 

map <F10>      :call DBGRrestart()<CR>
map <F11>      :call DBGRquit()<CR>

" commands
command! -nargs=* DBGRstart call DBGRstart("<args>")
command! -nargs=1 DBGRprint  call DBGRprint("<args>")
command! -nargs=1 DBGRprintExpand  call DBGRprint(<args>)
command! -nargs=1 DBGRcommand call DBGRcommand("<args>")

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
let g:DBGRprogramArgs     = ""
let g:DBGRconsoleHeight   = 7
let g:DBGRlineNumbers     = 1
let g:DBGRshowConsole     = 1

" script variables
let s:LINE_INFO       = "vimDebug:"
let s:COMPILER_ERROR  = "compiler error"
let s:RUNTIME_ERROR   = "runtime error"
let s:APP_EXITED      = "application exited"
let s:DBGR_READY      = "debugger ready"

let s:sessionId       = system("perl -e 'print int(rand(99999))'") " random num
let s:ctlFROMvdd      = ".ctl.vddTOvim." . s:sessionId " control fifo to read  from vdd
let s:ctlTOvdd        = ".ctl.vimTOvdd." . s:sessionId " control fifo to write to   vdd
let s:dbgFROMvdd      = ".dbg.vddTOvim." . s:sessionId " debug out fifo to read  from vdd
let s:dbgTOvdd        = ".dbg.vimTOvdd." . s:sessionId " debug out fifo to write to   vdd

let s:lineNumber      = 0
let s:fileName        = ""
let s:bufNr           = 0
let s:programDone     = 0

let s:consoleBufNr    = -99

" note that these aren't really arrays.  its a string.  different values are
" separated by s:sep.  manipulation of the 'array' is done with an array
" library: http://vim.sourceforge.net/script.php?script_id=171
let s:emptySignArray  = ""                           " array
let s:breakPointArray = ""                           " array
let s:sep             = "-"                          " array separator



" debugger functions
function! DBGRstart(...)
   if s:fileName != ""
      echo "\rthe debugger is already running"
      return
   endif

   " gather information and initialize script variables
   let g:DBGRprogramArgs = a:1
   let s:fileName  = bufname("%")                 " get file name
   let s:bufNr     = bufnr("%")                   " get buffer number
   let l:debugger  = s:DbgrName(s:fileName)       " get dbgr name
   if l:debugger == "none"
      return
   endif


   " build command
   let l:cmd = "vdd " . s:sessionId . " " . l:debugger . " '" . s:fileName . "'"
   let l:cmd = l:cmd . " " . g:DBGRprogramArgs

   " invoke the debugger
   exec "silent :! " . l:cmd . '&'

   " do after the system() call so that nongui vim doesn't show a blank screen
   echo "\rstarting the debugger..."

   " loop until vdd says the debugger is done loading
   while !filewritable(s:ctlFROMvdd)
      " this works in gvim but is misleading on the console
      " echo "\rwaiting for debugger to start (hit <C-c> to give up)..."
      continue
   endwhile
  "let l:debuggerReady = system('cat ' . s:ctlFROMvdd)

   if has("autocmd")
     autocmd VimLeave * call DBGRquit()
   endif

   if g:DBGRshowConsole == 1
      call DBGRopenConsole()
   endif

   redraw!
   call s:HandleCmdResult("started the debugger")
endfunction
function! DBGRnext()
   if !s:Copacetic()
      return
   endif
   echo "\rnext..."
   call system('echo "next" >> ' . s:ctlTOvdd) " send msg to vdd
   call s:HandleCmdResult()
endfunction
function! DBGRstep()
   if !s:Copacetic()
      return
   endif
   echo "\rstep..."
   call system('echo "step" >> ' . s:ctlTOvdd) " send msg to vdd
   call s:HandleCmdResult()
endfunction
function! DBGRcont()
   if !s:Copacetic()
      return
   endif
   echo "\rcontinue..."
   call system('echo "cont" >> ' . s:ctlTOvdd) " send msg to vdd
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


   " tell the debugger about the new break point
   "call system('echo "break:' . l:currLineNr . ':' . l:currFileName . '" >> ' . s:ctlTOvdd)
   silent exe "redir >> " . s:ctlTOvdd . '| echon "break:' . l:currLineNr . ':' . l:currFileName . '" | redir END'


   let s:breakPointArray = MvAddElement(s:breakPointArray, s:sep, l:id)

   " check if a currentLine sign is already placed
   if (s:lineNumber == l:currLineNr)
      exe "sign unplace " . l:id

      exe "sign place " . l:id . " line=" . l:currLineNr . " name=both file=" . l:currFileName
   else
      exe "sign place " . l:id . " line=" . l:currLineNr . " name=breakPoint file=" . l:currFileName
   endif

   "" block until the debugger is ready
   "let l:debuggerReady = system('cat ' . s:ctlFROMvdd)
   "redraw! | echo "\rbreakpoint set"

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


   " tell the debugger about the deleted break point
   "call system('echo "clear:' . l:currLineNr . ':' . l:currFileName . '" >> ' . s:ctlTOvdd)
   silent exe "redir >> " . s:ctlTOvdd . '| echon "clear:' . l:currLineNr . ':' . l:currFileName . '" | redir END'


   let s:breakPointArray = MvRemoveElement(s:breakPointArray, s:sep, l:id)
   exe "sign unplace " . l:id

   " place a currentLine sign if this is the currentLine
   if(s:lineNumber == l:currLineNr)
      exe "sign place " . l:id . " line=" . l:currLineNr . " name=currentLine file=" . l:currFileName
   endif

   "" block until the debugger is ready
   "let l:debuggerReady = system('cat ' . s:ctlFROMvdd)
   "redraw! | echo "\rbreakpoint disabled"

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

   silent exe "redir >> " . s:ctlTOvdd . '| echon "clearAll" | redir END'

   " do this in case the last current line had a break point on it
   call s:UnplaceTheLastCurrentLineSign()                " unplace the old sign
   call s:PlaceCurrentLineSign(s:lineNumber, s:fileName) " place the new sign

   "" block until the debugger is ready
   "let l:debuggerReady = system('cat ' . s:ctlFROMvdd)
   "redraw! | echo "\rall breakpoints disabled"

   call s:HandleCmdResult("all breakpoints disabled")
endfunction
function! DBGRprint(...)
   if !s:Copacetic()
      return
   endif
   if a:0 > 0
      call system("echo 'printExpression:" . a:1 . "' >> " . s:ctlTOvdd)
      call s:HandleCmdResult()
   endif
endfunction
function! DBGRcommand(...)
   if !s:Copacetic()
      return
   endif
   echo ""
   if a:0 > 0
      call system( "echo 'command:" . a:1 . "' >> " . s:ctlTOvdd )
      call s:HandleCmdResult()
   endif
endfunction
function! DBGRrestart()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   endif
   call system( 'echo "restart" >> ' . s:ctlTOvdd )
   " do after the system() call so that nongui vim doesn't show a blank screen
   echo "\rrestarting..."
   call s:UnplaceTheLastCurrentLineSign()
   redraw!
   call s:HandleCmdResult("restarted")
   let s:programDone = 0
endfunction
function! DBGRquit()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   endif

   " unplace all signs that were set in this debugging session
   call s:UnplaceBreakPointSigns()
   call s:UnplaceEmptySigns()
   call s:UnplaceTheLastCurrentLineSign()
   call s:SetNoLineNumbers()
   call DBGRcloseConsole()

   call system('echo "quit" >> ' . s:ctlTOvdd)

   if has("autocmd")
     autocmd! VimLeave * call DBGRquit()
   endif

   " reinitialize script variables
   let s:lineNumber      = 0
   let s:fileName        = ""
   let s:bufNr           = 0
   let s:programDone     = 0
   let s:sep             = "-"

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
" determine which debugger to invoke from the file extension
"
" returns debugger name or 'none' if there isn't a debugger available for
" that particular file extension.  (l:debugger is expected to match up
" with a perl class.  so, for example, if 'Jdb' is returned, there is
" hopefully a Jdb.pm out there somewhere where vdd can find it.
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
      return "none"
   endif

endfunction


function! s:HandleCmdResult(...)

   " get command results from control fifo
   let l:cmdResult = system('cat ' . s:ctlFROMvdd)
   " call confirm('cmdResult: ' . l:cmdResult, 'ok')

   if match(l:cmdResult, '^' . s:LINE_INFO . '\d\+:.*$') != -1
      let l:cmdResult = substitute(l:cmdResult, '^' . s:LINE_INFO, "", "")
      if a:0 <= 0 || (a:0 > 0 && match(a:1, 'breakpoint') == -1)
         call s:CurrentLineMagic(l:cmdResult)
      endif
      if a:0 > 0
         echo "\r" . a:1 . "                    "
      endif

   elseif l:cmdResult == s:APP_EXITED
      call s:HandleProgramTermination()
      redraw! | echo "\rthe application being debugged terminated"

   elseif match(l:cmdResult, '^' . s:COMPILER_ERROR) != -1
      " call confirm(substitute(l:cmdResult, '^' . s:COMPILER_ERROR, "", ""), "&Ok")
      call s:ConsolePrint(substitute(l:cmdResult, '^' . s:COMPILER_ERROR, "", ""))
      call DBGRquit()

   elseif match(l:cmdResult, '^' . s:RUNTIME_ERROR) != -1
      " call confirm(substitute(l:cmdResult, '^' . s:RUNTIME_ERROR, "", ""), "&Ok")
      call s:ConsolePrint(substitute(l:cmdResult, '^' . s:RUNTIME_ERROR, "", ""))
      call DBGRquit()

   elseif l:cmdResult == s:DBGR_READY
      if a:0 > 0
         echo "\r" . a:1 . "                    "
      endif

   else
      " i have to do this because of a vim redraw bug which clears the
      " messages i echo after returning.  grumble grumble.
      if match(l:cmdResult, "\n") != -1
         redraw!
         " call confirm(l:cmdResult, "&Ok")
         call s:ConsolePrint(l:cmdResult)
      else
         " echo l:cmdResult
         call s:ConsolePrint(l:cmdResult)
      endif

   endif

   " get results from debug out fifo
   let l:dbgOut = system('cat ' . s:dbgFROMvdd)
   call s:ConsolePrint(l:dbgOut)

   return
endfunction
" - gets lineNumber / fileName from the debugger
" - jumps to the lineNumber in the file, fileName
" - highlights the current line
"
" parameters
"    lineInfo: a string with the format 'lineNumber:fileName'
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
" returns nothing
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
" if the program being debugged has terminated, this function turns off the
" currentline sign but leaves the breakpoint signs on.
"
" sets s:programDone = 1.  so the only functions we should be calling
" after this situation is DBGRquit() or DBGRrestart().
function! s:HandleProgramTermination()
   call s:UnplaceTheLastCurrentLineSign()
   let s:lineNumber  = 0
   let s:bufNr       = 0
   let s:programDone = 1
endfunction


" debugger console functions
function! DBGRopenConsole()
   new "debugger console"
   let s:consoleBufNr = bufnr('%')
   exe "resize " . g:DBGRconsoleHeight
   exe "sign place 9999 line=1 name=empty buffer=" . s:consoleBufNr
   call s:SetLineNumbers()
   set buftype=nofile
   wincmd p
endfunction
function! DBGRcloseConsole()
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      return
   endif
   exe l:consoleWinNr . "wincmd w"
   q
endfunction
function! s:ConsolePrint(msg)
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
