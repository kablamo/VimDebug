" vimDebug.vim
"
" (c) eric johnson 09.31.2002
" distribution under the GPL
"
" email: vimDebug at iijo dot org
" http://iijo.org
"
" $Id: vimDebug.vim 63 2005-10-04 22:14:23Z eric $
"



" key bindings
map <F12>      :call DBGRstartVimDebuggerDaemon(' ')<cr>
map <Leader>s/ :DBGRstartVDD

map <F7>       :call DBGRstep()<CR>
map <F8>       :call DBGRnext()<CR>
map <F9>       :call DBGRcont()<CR>                          " continue

map <Leader>b  :call DBGRsetBreakPoint()<CR>
map <Leader>c  :call DBGRclearBreakPoint()<CR>
map <Leader>ca :call DBGRclearAllBreakPoints()<CR>

map <Leader>v/ :DBGRprintExpression 
map <Leader>v  :DBGRprintExpression2 expand("<cWORD>")<CR>   " print value
                                                             " of WORD under
                                                             " the cursor

map <Leader>/  :DBGRcommand 

map <F10>      :call DBGRrestart()<CR>
map <F11>      :call DBGRquit()<CR>


command! -nargs=* DBGRstartVDD call DBGRstartVimDebuggerDaemon(<f-args>)
command! -nargs=* DBGRprintExpression  call DBGRprintExpression(<f-args>)
command! -nargs=1 DBGRprintExpression2 call DBGRprintExpression(<args>)
command! -nargs=* DBGRprintExpression call DBGRprintExpression(<f-args>)
command! -nargs=* DBGRcommand call DBGRcommand(<f-args>)


" colors and symbols

" you may want to set SignColumn highlight in your .vimrc
" :help sign
" :help SignColumn

hi currentLine term=reverse cterm=reverse gui=reverse
hi breakPoint  term=NONE    cterm=NONE    gui=NONE
hi empty       term=NONE    cterm=NONE    gui=NONE

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

function! DBGRstartVimDebuggerDaemon(...)
   if s:fileName != ""
      echo "\rthe debugger is already running"
      return
   endif

   " gather information and initialize script variables
   let s:fileName  = bufname("%")                         " get file name
   let s:bufNr     = bufnr("%")                           " get buffer number
   let l:debugger  = DBGRgetDebuggerName(s:fileName)      " get dbgr name
   if l:debugger == "none"
      return
   endif

   " get program arguments
   let l:i = 1
   if a:0 == 0 || (a:0 == 1 && a:1 == " ")
      let g:DBGRprogramArgs = input('program arguments: ', g:DBGRprogramArgs)
   elseif l:i <= a:0
      let g:DBGRprogramArgs = ""
   endif
   while l:i <= a:0
      exe 'let g:DBGRprogramArgs = g:DBGRprogramArgs . " " . a:' . l:i . '"'
      let l:i = l:i + 1
   endwhile

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
   call DBGRhandleCmdResult("started the debugger")
endfunction

function! DBGRnext()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif
   echo "\rnext"

   call system('echo "next" >> ' . s:ctlTOvdd) " send msg to vdd

   call DBGRhandleCmdResult()
endfunction
function! DBGRstep()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif
   echo "\rstep"

   call system('echo "step" >> ' . s:ctlTOvdd) " send msg to vdd

   call DBGRhandleCmdResult()
endfunction
function! DBGRcont()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif
   echo "\rcontinue"

   call system('echo "cont" >> ' . s:ctlTOvdd) " send msg to vdd

   call DBGRhandleCmdResult()
endfunction

function! DBGRsetBreakPoint()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif


   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = DBGRcreateId(l:bufNr, l:currLineNr)


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

   call DBGRhandleCmdResult("breakpoint set")
endfunction
function! DBGRclearBreakPoint()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif


   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = DBGRcreateId(l:bufNr, l:currLineNr)


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

   call DBGRhandleCmdResult("breakpoint disabled")
endfunction
function! DBGRclearAllBreakPoints()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif

   call DBGRunplaceBreakPointSigns()

   let l:currFileName = bufname("%")
   let l:bufNr        = bufnr("%")
   let l:currLineNr   = line(".")
   let l:id           = DBGRcreateId(l:bufNr, l:currLineNr)

   silent exe "redir >> " . s:ctlTOvdd . '| echon "clearAll" | redir END'

   " do this in case the last current line had a break point on it
   call DBGRunplaceTheLastCurrentLineSign()              " unplace the old sign
   call DBGRplaceCurrentLineSign(s:lineNumber, s:fileName) " place the new sign

   "" block until the debugger is ready
   "let l:debuggerReady = system('cat ' . s:ctlFROMvdd)
   "redraw! | echo "\rall breakpoints disabled"

   call DBGRhandleCmdResult("all breakpoints disabled")
endfunction

function! DBGRprintExpression(...)
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif

   if a:0 > 0
      " build command
      let l:i = 1
      let l:expression = ""
      while l:i <= a:0
         exe 'let l:expression = l:expression . " " . a:' . l:i . '"'
         let l:i = l:i + 1
      endwhile

      call system("echo 'printExpression:" . l:expression . "' >> " . s:ctlTOvdd)

      call DBGRhandleCmdResult()
   endif

endfunction
function! DBGRcommand(...)
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   elseif s:programDone
      echo "\rthe application being debugged terminated"
      return
   endif

   echo ""

   if a:0 > 0
      " build command
      let l:i = 1
      let l:command = ""
      while l:i <= a:0
         exe 'let l:command = l:command . " " . a:' . l:i . '"'
         let l:i = l:i + 1
      endwhile

      " issue command to debugger
      call system( "echo 'command:" . l:command . "' >> " . s:ctlTOvdd )

      call DBGRhandleCmdResult()
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

   call DBGRunplaceTheLastCurrentLineSign()

   redraw!
   call DBGRhandleCmdResult("restarted")

   let s:programDone = 0
endfunction
function! DBGRquit()
   if s:fileName == ""
      echo "\rthe debugger is not running"
      return
   endif

   " unplace all signs that were set in this debugging session
   call DBGRunplaceBreakPointSigns()
   call DBGRunplaceEmptySigns()
   call DBGRunplaceTheLastCurrentLineSign()
   call DBGRsetNoLineNumbers()
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

function! DBGRplaceEmptySign()

   let l:id       = DBGRcreateId(bufnr("%"), "1")
   let l:fileName = bufname("%")

   if !MvContainsElement(s:emptySignArray, s:sep, l:id) == 1

      let s:emptySignArray = MvAddElement(s:emptySignArray, s:sep, l:id)
      exe "sign place " . l:id . " line=1 name=empty file=" . l:fileName

   endif

endfunction
function! DBGRunplaceEmptySigns()

   let l:oldBufNr = bufnr("%")
   call MvIterCreate(s:emptySignArray, s:sep, "VimDebugIteratorE")

   while MvIterHasNext("VimDebugIteratorE")
      let l:id         = MvIterNext("VimDebugIteratorE")
      let l:bufNr      = DBGRcalculateBufNrFromId(l:id)
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
function! DBGRunplaceBreakPointSigns()

   let l:oldBufNr = bufnr("%")
   call MvIterCreate(s:breakPointArray, s:sep, "VimDebugIteratorB")

   while MvIterHasNext("VimDebugIteratorB")
      let l:id         = MvIterNext("VimDebugIteratorB")
      let l:bufNr      = DBGRcalculateBufNrFromId(l:id)
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
function! DBGRsetLineNumbers()
   if g:DBGRlineNumbers == 1
      set number
   endif
endfunction
function! DBGRsetNoLineNumbers()
   if g:DBGRlineNumbers == 1
      set nonumber
   endif
endfunction
" place an empty sign on line 1 of the file
function! DBGRcreateId(bufNr, lineNumber)
   return a:bufNr * 10000000 + a:lineNumber
endfunction
function! DBGRcalculateBufNrFromId(id)
   return a:id / 10000000
endfunction
function! DBGRcalculateLineNumberFromId(id)
   return a:id % 10000000
endfunction
" determine which debugger to invoke from the file extension
"
" parameters
"    fileName
" returns debugger name or 'none' if there isn't a debugger available for
" that particular file extension.  (l:debugger is expected to match up
" with a perl class.  so, for example, if 'Jdb' is returned, there is
" hopefully a Jdb.pm out there somewhere where vdd can find it.
function! DBGRgetDebuggerName(fileName)

   let l:fileExtension = DBGRgetFileExtension(a:fileName)

   " consult file extension and filetype
   if     &l:filetype == "perl"   || l:fileExtension == ".pl"
      return "Perl"
   elseif &l:filetype == "c"      || l:fileExtension == ".c"   ||
        \ &l:filetype == "cpp"    || l:fileExtension == ".cpp"
      return "Gdb"
   elseif &l:filetype == "python" || l:fileExtension == ".py"
      return "Python"
   elseif &l:filetype == "ruby"   || l:fileExtension == ".r"
      return "Ruby"
   else
      echo "\rthere is no debugger associated with this file type"
      return "none"
   endif

endfunction
" can vim do this for me?  i wish it would
function! DBGRgetFileExtension(path)
   let l:temp = substitute(a:path, '\(^.*\/\)', "", "") " path
   let l:temp = substitute(l:temp, '^\.\+', "", "")     " dot files
   let l:temp = matchstr(l:temp, '\..*$')               " get extension
   let l:temp = substitute(l:temp, '^\..*\.', '.', '')  " remove > 1 extensions
   return l:temp
endfunction


function! DBGRhandleCmdResult(...)

   " get command results from control fifo
   let l:cmdResult = system('cat ' . s:ctlFROMvdd)

   if match(l:cmdResult, '^' . s:LINE_INFO . '\d\+:.*$') != -1
      let l:cmdResult = substitute(l:cmdResult, '^' . s:LINE_INFO, "", "")
      if a:0 <= 0 || (a:0 > 0 && match(a:1, 'breakpoint') == -1)
         call DBGRdoCurrentLineMagicStuff(l:cmdResult)
      endif
      if a:0 > 0
         echo "\r" . a:1 . "                    "
      endif

   elseif l:cmdResult == s:APP_EXITED
      call DBGRhandleProgramTermination()
      redraw! | echo "\rthe application being debugged terminated hoooo"

   elseif match(l:cmdResult, '^' . s:COMPILER_ERROR) != -1
      " call confirm(substitute(l:cmdResult, '^' . s:COMPILER_ERROR, "", ""), "&Ok")
      call DBGRprint(substitute(l:cmdResult, '^' . s:COMPILER_ERROR, "", ""))
      call DBGRquit()

   elseif match(l:cmdResult, '^' . s:RUNTIME_ERROR) != -1
      " call confirm(substitute(l:cmdResult, '^' . s:RUNTIME_ERROR, "", ""), "&Ok")
      call DBGRprint(substitute(l:cmdResult, '^' . s:RUNTIME_ERROR, "", ""))
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
         call DBGRprint(l:cmdResult)
      else
         " echo l:cmdResult
         call DBGRprint(l:cmdResult)
      endif

   endif

   " get results from debug out fifo
   let l:dbgOut = system('cat ' . s:dbgFROMvdd)
   call DBGRprint(l:dbgOut)

   return
endfunction
" - gets lineNumber / fileName from the debugger
" - jumps to the lineNumber in the file, fileName
" - highlights the current line
"
" parameters
"    lineInfo: a string with the format 'lineNumber:fileName'
" returns nothing
function! DBGRdoCurrentLineMagicStuff(lineInfo)

   let l:lineNumber = substitute(a:lineInfo, "\:.*$", "", "")
   let l:fileName   = substitute(a:lineInfo, "^\\d\\+\:", "", "")
   let l:fileName   = DBGRjumpToLine(l:lineNumber, l:fileName)

   " if there haven't been any signs placed in this file yet, place one the
   " user can't see on line 1 just to shift everything over.  otherwise, the
   " code will shift left when the old currentline sign is unplaced and then
   " shift right again when the new currentline sign is placed.  and thats
   " really annoying for the user.
   call DBGRplaceEmptySign()
   call DBGRunplaceTheLastCurrentLineSign()              " unplace the old sign
   call DBGRplaceCurrentLineSign(l:lineNumber, l:fileName) " place the new sign
   call DBGRsetLineNumbers()
   "z. " scroll page so that this line is in the middle

   " set script variables for next time
   let s:lineNumber = l:lineNumber
   let s:fileName   = l:fileName

endfunction
" the fileName may have been changed if we stepped into a library or some
" other piece of code in an another file.  load the new file if thats
" necessary and then jump to lineNumber
"
" parameters
"    lineNumber
"    fileName
" returns a fileName.
function! DBGRjumpToLine(lineNumber, fileName)
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
function! DBGRunplaceTheLastCurrentLineSign()
   let l:lastId = DBGRcreateId(s:bufNr, s:lineNumber)

   exe 'sign unplace ' . l:lastId

   " check if there was a break point at l:lastId
   if MvContainsElement(s:breakPointArray, s:sep, l:lastId) == 1
      exe "sign place " . l:lastId . " line=" . s:lineNumber . " name=breakPoint file=" . s:fileName
   endif

endfunction
" parameters
"    lineNumber
"    fileName
" returns nothing
function! DBGRplaceCurrentLineSign(lineNumber, fileName)

   " place the new currentline sign
   let l:bufNr = bufnr(a:fileName)
   let l:id    = DBGRcreateId(l:bufNr, a:lineNumber)

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
function! DBGRhandleProgramTermination()
   call DBGRunplaceTheLastCurrentLineSign()
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
   call DBGRsetLineNumbers()
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
function! DBGRprint(msg)
   let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   if l:consoleWinNr == -1
      "call confirm(a:msg, "&Ok")
      call DBGRopenConsole()
      let l:consoleWinNr = bufwinnr(s:consoleBufNr)
   endif
   exe l:consoleWinNr . "wincmd w"

   exe 'normal GA' . a:msg . ''
   normal G
   wincmd p
endfunction


