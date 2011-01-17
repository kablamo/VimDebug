" multvals.vim -- Array operations on Vim multi-values, or just another array.
" Author: Hari Krishna <hari_vim at yahoo dot com>
" Last Modified: 30-Jan-2003 @ 15:36
" Requires: Vim-6.0 or higher, genutils.vim(1.2) for sorting support.
" Version: 3.1.1
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Download From:
"     http://www.vim.org/script.php?script_id=171
" Summary Of Features:
"   Writer Functions:
"       MvAddElement
"       MvInsertElementAt
"       MvRemoveElement
"       MvRemovePattern
"       MvRemoveElementAt
"       MvRemoveElementAll
"       MvReplaceElementAt
"       MvPushToFront
"       MvPushToFrontElementAt
"       MvPullToBack
"       MvPullToBackElementAt
"       MvRotateLeftAt
"       MvRotateRightAt
"       MvSwapElementsAt
"       MvQSortElements
"
"   Reader Functions:
"       MvNumberOfElements
"       MvStrIndexOfElement
"       MvStrIndexOfPattern
"       MvStrIndexAfterElement
"       MvStrIndexAfterPattern
"       MvStrIndexOfElementAt
"       MvIndexOfElement
"       MvIndexOfPattern
"       MvContainsElement
"       MvContainsPattern
"       MvElementAt
"       MvLastElement
"       MvIterCreate
"       MvIterDestroy
"       MvIterHasNext
"       MvIterNext
"       MvCmpByPosition
"       MvPromptForElement
"       MvPromptForElement2
"
" Usage:
"   - An array is nothing but a string of multiple values separated by a
"     pattern.  The simplest example being Vim's multi-value variables such as
"     tags. You can use the MvAddElement() function to create an array.
"     However, there is nothing special about this function, you can as well
"     make up the string by simply concatinating elements with the chosen
"     pattern as a separator.
"   - The separator can be any regular expression. However, if a regular
"     expression is used as a separtor, you need to pass in a second separator,
"     which is a plain string that guarantees to match the separator regular
"     expression, as an additional argument (which was not the case with
"     earlier versions). When the array needs to be modified (which is
"     internally done by some of the reader functions also) this sample
"     separator is used to preserve the integrity of the array.
"   - If you for example want to go over the words in a sentence, then an easy
"     way would be to treat the sentence as an array with '\s\+' as a
"     separator pattern. Be sure not to have zero-width expressions in the
"     pattern as these would otherwise confuse the plugin.
"   - Suggested usage to go over the elements is to use the iterater functions
"     as shows in the below example
"     Ex Usage:
"       " The below pattern avoids protected comma's from getting treated as
"       separators.
"       call MvIterCreate(&tags, "\\\@<!\(\\\\\)*\zs,", "Tags", ',')
"     	while MvIterHasNext("Tags")
"     	  call input("Next element: " . MvIterNext("Tags"))
"     	endwhile
"     	call MvIterDestroy("Tags")
"
" ALMOST ALL OPERATIONS TAKE THE ARRAY AND THE SEPARATOR AS THE FIRST TWO
"   ARGUMENTS.
" All element-indexes start from 0 (like in C++ or Java).
" All string-indexes start from 0 (as it is for Vim built-in functions).
"
" Changes in 3.0:
"   - All functions can now be used with regular expressions as patterns.
"   - There is an API change. All functions now require a sample regular
"     separator to be passed in when using a regular expression as a separator
"     string. There is no impact if you don't use regular expressions as
"     separators.
"   - Some of the functions now have a variant that take a regex pattern
"     instead of an existing element.
"   - Fixed a bug in MvPromptForElement that was introduced in the previous
"     change, that sometimes ignores the last line in the prompt string.
" Changes in 2.3:
"   - A variant of MvPromptForElement to specify the number of columns that
"     you want the elements to be formatted in.
"   - New functions MvQSortElements() and MvSwapElementsAt() 
"   - Worked-around a bug in vim that effects MvElementAt() for last element
"     in a large array.
" Changes in 2.1.1:
"   - Now all the operations work correctly with elements that have special
"     chars in them.
" Changes in 2.1.0:
"   - Improved the read-only operations to work with regular expressions as
"     patterns.
" Changes in 2.0.3:
"   - Fixed bugs in MvStrIndexOfElement(), MvIterHasNext() and MvCmpByPosition()
" Changes in 2.0.3:
"   - New functions were added.
"   - The order of arguments for MvIterCreate has been changed for the sake of
"       consistency.
"   - Prefixed all the global functions with "Mv" to avoid global name
"       conflicts.
"
" TODO:
"   Need a function to extract patterns, MvElementLikePattern().
"   More testing is required for regular expressions as separators.
"   Some performance improvement should be possible in: MvElementAt,
"     MvSwapElementsAt, MvQSortElements, MvPushToFront (and friends)
"   Using '\%(\s\|\n\)\+' as separator pattern for a block of text containing
"     newlines doesn't detect newlines as a separtor.
"
"

if exists("loaded_multvals")
  finish
endif
let loaded_multvals = 1

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim

function! s:MyScriptId()
  map <SID>xx <SID>xx
  let s:sid = maparg("<SID>xx")
  unmap <SID>xx
  return substitute(s:sid, "xx$", "", "")
endfunction
let s:myScriptId = s:MyScriptId()
delfunction s:MyScriptId

" Writer functions {{{

" Adds an element and returns the new array.
" Params:
"   ele - Element to be added to the array.
" Returns:
"   the new array.
function! MvAddElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  return array . a:ele . sep
endfunction


" Insert the element before index and return the new array. Index starts from 0.
" Params:
"   ele - Element to be inserted into the array.
"   index - The index before which the element should be inserted.
" Returns:
"   the new array.
function! MvInsertElementAt(array, sep, ele, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  if a:index == 0
    return a:ele . sep . array
  else
    let strIndex = MvStrIndexOfElementAt(array, a:sep, a:index, sep)
    if strIndex < 0
      return array
    endif

    let sub1 = strpart(array, 0, strIndex)
    let sub2 = strpart(array, strIndex, strlen(array))
    return sub1 . a:ele . sep . sub2
  endif
endfunction


" Removes the element and returns the new array.
" Params:
"   ele - Element to be removed from the array.
" Returns:
"   the new array.
function! MvRemoveElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvRemoveElementImpl(a:array, a:sep, a:ele, 0, sep)
endfunction

" Same as MvRemoveElement, except that the element that
"   matches the passed in pattern is removed.
function! MvRemovePattern(array, sep, pat, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvRemoveElementImpl(a:array, a:sep, a:pat, 1, sep)
endfunction

function! s:MvRemoveElementImpl(array, sep, ele, asPattern, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  if a:asPattern
    let strIndex = MvStrIndexOfPattern(array, a:sep, a:ele, sep)
    let strAfterIndex = MvStrIndexAfterPattern(array, a:sep, a:ele, sep)
  else
    let strIndex = MvStrIndexOfElement(array, a:sep, a:ele, sep)
    let strAfterIndex = MvStrIndexAfterElement(array, a:sep, a:ele, sep)
  endif
  " First remove this element.
  if strIndex != -1
    let sub = strpart(array, 0, strIndex)
    let sub = sub . strpart(array, strAfterIndex, strlen(array))
  else
    let sub = array
  endif
  return sub
endfunction


" Remove the element at index. Index starts from 0.
" Params:
"   index - The index of the element that needs to be removed.
" Returns:
"   the new array.
function! MvRemoveElementAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let ele = MvElementAt(a:array, a:sep, a:index, sep)
  return MvRemoveElement(a:array, a:sep, ele, sep)
endfunction


" Remove the all occurances of element in array.
" Contributed by Steve Hall <digitect at mindspring.com>
" Params:
"   ele - Element to be removed from the array.
" Returns:
"   the new array.
function! MvRemoveElementAll(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = a:array
  while MvContainsElement(array, a:sep, a:ele, sep) == 1
    let array = MvRemoveElement(array, a:sep, a:ele, sep)
  endwhile
  return array
endfunction


" Replace the element at index with element
" Contributed by Steve Hall <digitect at mindspring.com>
" Params:
"   ele - The new element to replace in the array.
"   index - The index of the element that needs to be replaced.
" Returns:
"   the new array.
function! MvReplaceElementAt(array, sep, ele, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  " insert element
  let array = MvInsertElementAt(a:array, a:sep, a:ele, a:index, sep)
  " remove element following
  let array = MvRemoveElementAt(array, a:sep, a:index + 1, sep)
  return array
endfunction


" Rotates the array such that the element at index is on the left (the first).
" Params:
"   index - The index of the element that needs to be rotated.
" Returns:
"   the new array.
function! MvRotateLeftAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:index <= 0 " If index is 0, there is nothing that needs to be done.
    return a:array
  endif

  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  let strIndex = MvStrIndexOfElementAt(array, a:sep, a:index, sep)
  if strIndex < 0
    return array
  endif
  return strpart(array, strIndex) . strpart(array, 0, strIndex)
endfunction


" Rotates the array such that the element at index is on the right (the last).
" Params:
"   index - The index of the element that needs to be rotated.
" Returns:
"   the new array.
function! MvRotateRightAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:index < 0
    return a:array
  endif

  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  let strIndex = MvStrIndexOfElementAt(array, a:sep, a:index + 1, sep)
  if strIndex < 0
    return array
  endif
  return strpart(array, strIndex) . strpart(array, 0, strIndex)
endfunction


" Moves the element to the front of the array. Useful for maintaining an MRU
"  list. Even if the element doesn't exist in the array, it is still added to
"  the front of the array. See selectbuf.vim at vim.sf.net for an example
"  usage.
" Params:
"   ele - Element that needs to be pushed to the front.
" Returns:
"   the new array.
function! MvPushToFront(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = MvRemoveElement(a:array, a:sep, a:ele, sep)
  let array = a:ele . sep . array
  return array
endfunction


" Moves the element at the specified index to the front of the array. Useful
"  for maintaining an MRU list. Even if the element doesn't exist in the array,
"  it is still added to the front of the array. See selectbuf.vim at vim.sf.net
"  for an example usage.
" Params:
"   index - Index of the element that needs to moved to the front of the array.
" Returns:
"   the new array.
function! MvPushToFrontElementAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let ele = MvElementAt(a:array, a:sep, a:index, sep)
  return MvPushToFront(a:array, a:sep, ele, sep)
endfunction


" Moves the element to the back of the array. Even if the element doesn't exist
"   in the array, it is still added to the back of the array.
" Params:
"   ele - Element that needs to be pulled to the back.
" Returns:
"   the new array.
function! MvPullToBack(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = s:EnsureTrailingSeparator(
	\ MvRemoveElement(a:array, a:sep, a:ele, sep), a:sep, sep)
  let array = array . a:ele . sep
  return array
endfunction


" Moves the element at the specified index to the back of the array. Even if
"   the element doesn't exist in the array, it is still added to the back of
"   the array.
" Params:
"   index - Index of the element that needs to moved to the back of the array.
" Returns:
"   the new array.
function! MvPullToBackElementAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let ele = MvElementAt(a:array, a:sep, a:index, sep)
  return MvPullToBack(a:array, a:sep, ele, sep)
endfunction


" Swaps the elements at the specified indexes.
" Params:
"   index1 - index of one of the elements.
"   index2 - index of the other element.
" Returns:
"   the new array with swapped elements.
function! MvSwapElementsAt(array, sep, index1, index2, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let array = s:EnsureTrailingSeparator(a:array, a:sep, sep)
  if a:index1 == a:index2
    return array
  endif

  if a:index1 > a:index2
    let index1 = a:index2
    let index2 = a:index1
  else
  let index1 = a:index1
  let index2 = a:index2
  endif
  let ele1 = MvElementAt(a:array, a:sep, index1, sep)
  let ele2 = MvElementAt(a:array, a:sep, index2, sep)
  let array = MvRemoveElement(a:array, a:sep, ele1, sep)
  let array = MvRemoveElement(array, a:sep, ele2, sep)
  if index1 >= MvNumberOfElements(array, a:sep, sep)
    let array = MvAddElement(array, a:sep, ele2, sep)
  else
    let array = MvInsertElementAt(array, a:sep, ele2, index1, sep)
  endif
  if index2 >= MvNumberOfElements(array, a:sep, sep)
    let array = MvAddElement(array, a:sep, ele1, sep)
  else
    let array = MvInsertElementAt(array, a:sep, ele1, index2, sep)
  endif
  return array
endfunction


" Sorts the elements in the array using the given comparator and in the given
"   direction using quick sort algorithm.
" Ex:
"   The following sorts the numbers in descending order using the bundled number
"   comparator (see genutils.vim).
"
"     echo MvQSortElements('3,4,2,5,7,1,6', ',', 's:CmpByNumber', -1)
"
"   The following sorts the alphabet in ascending order again using the
"   bundled string comparator (see genutils.vim).
"
"     echo MvQSortElements('e,a,d,b,f,c,g', ',', 's:CmpByString', 1)
"
" Params:
"   cmp - name of the comparator function. You can use the names of standard
"	  comparators specified in the genutils.vim script, such as
"	  's:CmpByString', or define your own (which then needs to be a global
"	  function or if it is a script local function, prepend it with your
"	  script id. See genutils.vim for how to get your script id and for
"	  examples on comparator functions (if you want to write your own).
"   direction - 1 for asending and -1 for descending.
" Returns:
"   The new sorted array.
" See:
"   QSort2() function from genutils.vim
function! MvQSortElements(array, sep, cmp, direction, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  let s:arrayForSort{'array'} = a:array
  let s:arrayForSort{'sep'} = a:sep
  let s:arrayForSort{'samplesep'} = sep
  let nElements = MvNumberOfElements(a:array, a:sep, sep)
  " Create an array containing indirection indexes.
  let s:sortArrayIndexes = ''
  let i = 0
  while i < nElements
    let s:sortArrayIndexes = s:sortArrayIndexes . i . ','
    let i = i + 1
  endwhile
  call QSort2(1, nElements, a:cmp, a:direction,
	\ s:myScriptId . 'SortGetElementAt', s:myScriptId . 'SortSwapElements',
	\ '')

  " Finally reconstruct the array from the sorted indexes.
  let array = ''
  let nextEle = ''
  call MvIterCreate(s:sortArrayIndexes, ',', 'MvQSortElements', sep)
  while MvIterHasNext('MvQSortElements')
    let nextEle = MvElementAt(a:array, a:sep, MvIterNext('MvQSortElements'), sep)
    let array = MvAddElement(array, sep, nextEle)
  endwhile
  call MvIterDestroy('MvQSortElements')
  return array
endfunction


function! s:SortGetElementAt(index, context)
  let index = MvElementAt(s:sortArrayIndexes, ',', a:index - 1)
  return MvElementAt(s:arrayForSort{'array'}, s:arrayForSort{'sep'}, index,
	\ s:arrayForSort{'samplesep'})
endfunction


function! s:SortSwapElements(index1, index2, context)
  let s:sortArrayIndexes = MvSwapElementsAt(s:sortArrayIndexes, ',',
	\ a:index1 - 1, a:index2 - 1)
endfunction

" Writer functions }}}


" Reader functions {{{

" Functions that are at the bottom of the stack, these don't use others {{{

" Returns the number of elements in the array.
" Returns:
"   the number of elements that are present in the array.
function! MvNumberOfElements(array, sep, ...)
  let array = a:array
  let pat = '\%(.\)\{-}\%(' . a:sep . '\)\{-1\}'

  " Replace all the elements and the following separator with 'x' and count
  " the number of 'x's. If the last one isn't followed by a separator, it will
  " not be replaced with an 'x'.
  let mod = substitute(array, pat, 'x', 'g')
  if strridx(mod, 'x') != (strlen(mod) - 1)
    let nElements = strlen(matchstr(mod, '^x*')) + 1
  else
    let nElements = strlen(mod)
  endif
  return nElements
endfunction


" Returns the string-index of the element in the array, which can be used with
"   string manipulation functions such as strpart().
" Params:
"   ele - Element whose string-index is to be found.
" Returns:
"   the string index of the element, starts from 0.
function! MvStrIndexOfElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvStrIndexOfElementImpl(a:array, a:sep, a:ele, 0, sep)
endfunction

" Same as MvStrIndexOfElement, except that the string index of element that
"   matches the passed in pattern is found.
function! MvStrIndexOfPattern(array, sep, pat, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvStrIndexOfElementImpl(a:array, a:sep, a:pat, 1, sep)
endfunction

function! s:MvStrIndexOfElementImpl(array, sep, ele, asPattern, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:asPattern
    let ele = a:ele
  else
    let ele = s:Escape(a:ele)
  endif
  let array = sep . s:EnsureTrailingSeparator(a:array, a:sep, sep)
  let sub = matchstr(array, a:sep . ele . a:sep)
  return stridx(array, sub) + strlen(matchstr(sub, '^' . a:sep)) - strlen(sep)
endfunction


" Returns the index after the element.
" Params:
"   ele - Element after which the index needs to be found.
" Returns:
"   the string index after the element including the separator. Starts from 0.
"     Returns -1 if there is no such element. Returns one more than the last
"     char if it is the last element (like matchend()).
function! MvStrIndexAfterElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvStrIndexAfterElementImpl(a:array, a:sep, a:ele, 0, sep)
endfunction

" Same as MvStrIndexAfterElement, except that the string index after element
"   that matches the passed in pattern is found.
function! MvStrIndexAfterPattern(array, sep, pat, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvStrIndexAfterElementImpl(a:array, a:sep, a:pat, 1, sep)
endfunction

function! s:MvStrIndexAfterElementImpl(array, sep, ele, asPattern, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:asPattern
    let ele = a:ele
  else
    let ele = s:Escape(a:ele)
  endif
  let array = sep . s:EnsureTrailingSeparator(a:array, a:sep, sep)
  let index = matchend(array, a:sep . ele . a:sep)
  if index == strlen(array) && ! s:HasTrailingSeparator(a:array, a:sep)
    let index = index - strlen(sep)
  endif
  if index != -1
    return index - strlen(sep)
  endif
  return index
endfunction


" Returns the last element in the array.
" Returns:
"   the last element in the array.
function! MvLastElement(array, sep, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  " Remove the last separator.
  let array = a:array
  let lastSepIndx = match(a:array, a:sep . '$')
  if lastSepIndx != -1
    let array = strpart(a:array, 0, lastSepIndx)
  endif
  let pat = '\%(.\)\{-}\%(' . a:sep . '\)\{-1\}'
  " Remove the last element but everything else.
  return substitute(array, pat, '', 'g')
endfunction

" Functions that are at the bottom of the stack }}}

" Returns the string-index of the element present at element-index, which can
"   be used with string manipulation functions such as strpart().
" Params:
"   index - Index of the element whose string-index needs to be found.
" Returns:
"   the string index of the element, starts from 0.
function! MvStrIndexOfElementAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:index < 0
    return -1
  elseif a:index == 0
    return 0
  endif

  let prevEle = MvElementAt(a:array, a:sep, a:index - 1, sep)
  return MvStrIndexAfterElement(a:array, a:sep, prevEle, sep)
endfunction


" Returns the element-index of the element in the array, which can be used with
"   other functions that accept element-index such as MvInsertElementAt,
"   MvRemoveElementAt etc.
" Params:
"   ele - Element whose element-index is to be found.
" Returns:
"   the element-index of the element, starts from 0.
function! MvIndexOfElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvIndexOfElementImpl(a:array, a:sep, a:ele, 0, sep)
endfunction

" Same as MvIndexOfElement, except that the index of element that matches
"   the passed in pattern is found.
function! MvIndexOfPattern(array, sep, pat, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return s:MvIndexOfElementImpl(a:array, a:sep, a:pat, 1, sep)
endfunction

function! s:MvIndexOfElementImpl(array, sep, ele, asPattern, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:asPattern
    let strIndex = MvStrIndexOfPattern(a:array, a:sep, a:ele, sep)
  else
    let strIndex = MvStrIndexOfElement(a:array, a:sep, a:ele, sep)
  endif
  if strIndex < 0
    return -1
  endif

  let sub = strpart(a:array, 0, strIndex)
  return MvNumberOfElements(sub, a:sep, sep)
endfunction


" Returns 1 (for true) if the element is contained in the array and 0 (for
"   false) if not.
" Params:
"   ele - Element that needs to be tested for.
" Returns:
"   1 if element is contained and 0 if not.
function! MvContainsElement(array, sep, ele, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if MvStrIndexOfElement(a:array, a:sep, a:ele, sep) >= 0
    return 1
  else
    return 0
  endif
endfunction

" Same as MvContainsElement, except that the element that matches the passed
"   in pattern is checked.
function! MvContainsPattern(array, sep, pat, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if MvStrIndexOfPattern(a:array, a:sep, a:pat, sep) >= 0
    return 1
  else
    return 0
  endif
endfunction


" Returns the index'th element in the array. The index starts from 0.
" Inspired by the posts in the vimdev mailing list, by Charles E. Campbell &
"   Zdenek Sekera.
" Params:
"   index - Index at which the element needs to be found.
" Returns:
"   the element at the given index.
function! MvElementAt(array, sep, index, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if a:index < 0
    return ""
  endif
  let index = a:index + 1
  let array = a:array

  let nElements = MvNumberOfElements(array, a:sep, sep)
  if index > nElements
    return ""
  endif

  let sub = ""
  if nElements == 1
    if ! s:HasTrailingSeparator(array, a:sep)
      let sub = array
    else
      let sub = strpart(array, 0,
                  \ (strlen(array) - strlen(matchstr(array, a:sep))))
    endif

  " Work-around for vim taking too long for last element, if the string is
  "   huge.
  elseif index > 1 && index == nElements " Last element.
    " Extract upto the previous element.
    let pat1 = '\(\(.\{-}' . a:sep . '\)\{' . (index - 1) . '}\).*$'
    let sub1 = substitute(array, pat1, '\1','')
    if strlen(sub1) != 0
      let sub2 = strpart(array, strlen(sub1))
      if strlen(sub2) != 0
	let ind = match(sub2, a:sep)
	if ind == -1
	  let sub = sub2
	else
	  let sub = strpart(sub2, 0, ind)
	endif
      endif
    endif
  else
    let pat1 = '\(\(.\{-}' . a:sep . '\)\{' . index . '}\).*$'
    " Extract upto this element.
    let sub1 = substitute(array, pat1, '\1','')
    if strlen(sub1) != 0 && index > 1
      let pat2 = '\(\(.\{-}' . a:sep . '\)\{' . (index - 1) . '}\).*$'
      " Extract upto the previous element.
      let sub2 = substitute(sub1, pat2, '\1','')
      if strlen(sub2) != 0
        let sub3 = strpart(sub1, strlen(sub2))
        if s:HasTrailingSeparator(sub3, a:sep)
          let sub = strpart(sub3, 0,
                  \ (strlen(sub3) - strlen(matchstr(sub3, a:sep))))
        else
          let sub = sub3
        endif
      endif
    else
      let sub = strpart(sub1, 0,
                  \ (strlen(sub1) - strlen(matchstr(sub1, a:sep))))
    endif
  endif
  return sub
endfunction


" Creates a new iterator with the given name. This can be passed to
"   MvIterHasNext() and MvIterNext() to iterate over elements. Call MvIterDestroy()
"   to remove the space occupied by this iterator.
" Do not modify the array while using the iterator.
" Params:
"   iterName - A unique name that is used to identify this iterator. The
"                storage is alloted in the script name space (for Vim 6.0 or
"                above) or in the global name space (for previous Vim versions).
function! MvIterCreate(array, sep, iterName, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  exec "let " . s:GetVarForIter(a:iterName) . "_array = a:array"
  exec "let " . s:GetVarForIter(a:iterName) . "_sep = a:sep"
  exec "let " . s:GetVarForIter(a:iterName) . "_samplesep = sep"
  exec "let " . s:GetVarForIter(a:iterName) . "_max = " .
        \ MvNumberOfElements(a:array, a:sep, sep)
  exec "let " . s:GetVarForIter(a:iterName) . "_curIndex = 0"
endfunction


" Deallocates the space occupied by this iterator.
" Params:
"   iterName - The name of the iterator to be destroyed that was previously
"                created using MvIterCreate.
function! MvIterDestroy(iterName)
  exec "unlet " . s:GetVarForIter(a:iterName) . "_array"
  exec "unlet " . s:GetVarForIter(a:iterName) . "_sep"
  exec "unlet " . s:GetVarForIter(a:iterName) . "_samplesep"
  exec "unlet " . s:GetVarForIter(a:iterName) . "_max"
  exec "unlet " . s:GetVarForIter(a:iterName) . "_curIndex"
endfunction


" Indicates if there are more elements in this array to be iterated. Always
"   call this before calling MvIterNext().
" Do not modify the array while using the iterator.
" Params:
"   iterName - The name of the iterator that was previously created using
"                MvIterCreate.
" Returns:
"   1 (for true) if has more elements or 0 (for false).
function! MvIterHasNext(iterName)
  if ! exists(s:GetVarForIter(a:iterName) . "_curIndex")
    return 0
  endif

  exec "let max = " . s:GetVarForIter(a:iterName) . "_max"
  if max == 0
    return 0
  endif

  exec "let curIndex = " . s:GetVarForIter(a:iterName) . "_curIndex"
  if curIndex < max
    return 1
  else
    return 0
  endif
endfunction


" Returns next value or "" if none. You should always call MvIterHasNext()
"   before calling this function.
" Do not modify the array while using the iterator.
" Params:
"   iterName - The name of the iterator that was previously created using
"                MvIterCreate.
" Returns:
"   the next element in the iterator (array).
function! MvIterNext(iterName)
  if ! exists(s:GetVarForIter(a:iterName) . "_curIndex")
    return ""
  endif

  exec "let curIndex = " . s:GetVarForIter(a:iterName) . "_curIndex"
  exec "let array = " . s:GetVarForIter(a:iterName) . "_array"
  exec "let sep = " . s:GetVarForIter(a:iterName) . "_sep"
  exec "let samplesep = " . s:GetVarForIter(a:iterName) . "_samplesep"
  if curIndex >= 0
    let ele = MvElementAt(array, sep, curIndex, samplesep)
    exec "let " . s:GetVarForIter(a:iterName) . "_curIndex = " . (curIndex + 1)
  else
    let ele = ""
  endif
  return ele
endfunction


" Compares two elements based on the order of their appearance in the array.
"   Useful for sorting based on an MRU listing.
" Params:
"   ele1 - first element to be compared by position.
"   ele2 - second element to be compared by position.
"   direction - the direction of sort, used for determining the return value.
" Returns:
"   direction if ele2 comes before ele1 (for no swap), and 0 or -direction
"     otherwise (for swap).
function! MvCmpByPosition(array, sep, ele1, ele2, direction, ...)
  let strIndex1 = MvStrIndexOfElement(a:array, a:sep, a:ele1)
  let strIndex2 = MvStrIndexOfElement(a:array, a:sep, a:ele2)

  if (strIndex1 == -1) && (strIndex2 != -1)
    let strIndex1 = strIndex2 + a:direction
  elseif (strIndex1 != -1) && (strIndex2 == -1)
    let strIndex2 = strIndex1 + a:direction
  endif

  if strIndex1 < strIndex2
    return -a:direction
  elseif strIndex1 > strIndex2
    return a:direction
  else
    return 0
  endif
endfunction


" Function to prompt user for an element out of the passed in array. The
"   user will be prompted with a list of choices to make. The elements are
"   formatted in a single column with a number prefixed to them. User can
"   then enter the numer of the element to indicate the selection. Take a
"   look at the remcmd.vim script at vim.sf.net for an example usage.
" Params:
"   default - The default value for the selection. Default can be the
"               element-index or the element itself. If number, it is always
"               treated as an index, so if the elements are composed of
"               numbers themselves, then you need to compute the index before
"               calling this function.
"   msg - The message that should appear in the prompt (passed to input()).
"   skip - The element that needs to be skipped from selection (pass a
"            non-existent element to disable this, such as an empty value '').
"   useDialog - if true, uses dialogs for prompts, instead of the command-line(
"                 inputdialog() instead of input()). But personally, I don't
"                 like this because the power user then can't use the
"                 expression register.
" Returns:
"   the selected element or empty string, "" if nothing is selected.
"
function! MvPromptForElement(array, sep, default, msg, skip, useDialog, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  return MvPromptForElement2(a:array, a:sep, a:default, a:msg, a:skip,
	\ a:useDialog, 1, sep)
endfunction


" Same as above MvPromptForElement, except that you can tell the number of
"   columns that you want the elements to be formatted into.
function! MvPromptForElement2(array, sep, default, msg, skip, useDialog, nCols,
      \ ...)
  let sep = (a:0 == 0) ? a:sep : a:1

  let nCols = a:nCols
  let index = 0
  let line = ""
  let element = ""
  let optionsMsg = ""
  let colWidth = &columns / nCols - 1 " Leave a margin of one column as a gap.
  let curCol = 1
  let nElements = MvNumberOfElements(a:array, a:sep, sep)
  let newArray = "" " Without the skip element.
  if MvContainsElement(a:array, a:sep, a:skip, sep)
    let nElements = nElements - 1
  endif
  call MvIterCreate(a:array, a:sep, "MvPromptForElement", sep)
  while MvIterHasNext("MvPromptForElement")
    let element = MvIterNext("MvPromptForElement")
    if element == a:skip
      continue
    endif
    let newArray = newArray . element . sep
    let element = index . s:Spacer(4 - s:nDigits(index)) . element
    let eleColWidth = (strlen(element) - 1) / colWidth + 1
    " Fill up the spacer for the rest of the partial column.
    let element = element . s:Spacer(
	  \ eleColWidth * (colWidth + 1) - strlen(element) - 1)
    let wouldBeLength = strlen(line) + strlen(element) + 1
    if wouldBeLength > (curCol * (colWidth + eleColWidth)) &&
	  \ wouldBeLength > &columns
      let splitLine = 2 " Split before adding the new element.
    elseif curCol == nCols
      let splitLine = 1 " Split after adding the new element.
    else
      let splitLine = 0
    endif
    if splitLine == 2
      if strlen(line) == &columns
	" Remove the last space as it otherwise results in an extra empty line
	" on the screen.
	let line = strpart(line, 0, strlen(line) - 1)
      endif
      let optionsMsg = optionsMsg . line . "\n"
      let line = element . ' '
      let curCol = strlen(element) / (colWidth + 1)
    else
      let line = line . element . ' '
      if splitLine == 1
	if strlen(line) == &columns
	  " Remove the last space as it otherwise results in an extra empty line
	  " on the screen.
	  let line = strpart(line, 0, strlen(line) - 1)
	endif
	let curCol = 0 " Reset col count.
	let optionsMsg = optionsMsg . line . "\n"
	let line = ""
      endif
    endif
    let curCol = curCol + 1
    let index = index + 1
  endwhile
  " Finally if there is anything left in line, then append that too.
  if line != ""
    let optionsMsg = optionsMsg . line . "\n"
    let line = ""
  endif
  call MvIterDestroy("MvPromptForElement")

  let default = ''
  if match(a:default, '^\d\+$') != -1
    let default = a:default + 0
  elseif a:default != ''
    let default = MvIndexOfElement(a:array, a:sep, a:default, sep)
  endif
  if a:default == -1
    let default = ""
  endif

  while !exists("selectedElement")
    if a:useDialog
      let selection = inputdialog(optionsMsg . a:msg, default) + 0
    else
      let selection = input(optionsMsg . a:msg, default)
    endif

    if selection == ""
      let selectedElement = ""
    else
      let selection = selection + 0
      if selection >= 0 && selection < nElements
	let selectedElement = MvElementAt(newArray, sep, selection)
      else
	echohl ERROR | echo "\nInvalid selection, please try again" |
	      \ echohl NONE
      endif
    endif
    echo "\n"
  endwhile
  return selectedElement
endfunction
 
" Reader functions }}}


" Utility functions {{{

function! s:GetVarForIter(iterName)
  if v:version < 600
    return "g:" . a:iterName
  else
    return "s:" . a:iterName
  endif
endfunction


" Make sure the array ha a trailing separator, returns the new array.
function! s:EnsureTrailingSeparator(array, sep, ...)
  let sep = (a:0 == 0) ? a:sep : a:1
  if strlen(a:array) == 0
    return a:array
  endif

  let exists = 1
  if ! s:HasTrailingSeparator(a:array, a:sep)
    let array = a:array . sep
  else
    let array = a:array
  endif
  return array
endfunction


function! s:HasTrailingSeparator(array, sep)
  return match(a:array, a:sep . '$') != -1
endfunction


function! s:IsRegularExpression(str)
  return match(a:str, '[.\\[\]{}*^$~]') != -1
endfunction


function! s:Escape(str)
  return escape(a:str, "\\.[^$~")
endfunction


function! s:Spacer(width)
  return strpart("                                                            ",
	\ 0, a:width)
endfunction


function! s:nDigits(num)
  " I know log() can be used, but since log() is not available, what is the
  " other way finding this?
  return (a:num < 10)
	\ ? 1
	\ : (a:num < 100)
	\   ? 2
	\   : (a:num < 1000)
	\     ? 3
	\     : 4
endfunction

" Utility functions }}}


" Testing {{{
"function! s:Assert(actual, expected, msg)
"  if a:actual != a:expected
"    call input("Failed: " . a:msg. ": actual: " . a:actual . " expected: " . a:expected)
"  endif
"endfunction
"
"function! MvTestPrintAllWithIter(array, sep)
"  let elementCount = 0
"  call MvIterCreate(a:array, a:sep, "MyIter")
"  while MvIterHasNext("MyIter")
"    call s:Assert(MvIterNext("MyIter"), elementCount+1, "MvIterNext with array: " . a:array . " and sep: " . a:sep . " for " . (elementCount+1))
"    let elementCount = elementCount + 1
"  endwhile
"  call MvIterDestroy("MyIter")
"endfunction
"
"function! MvRunTests()
"  call MvTestPrintAllWithIter('1,,2,,3,,4,,', ',,')
"  call MvTestPrintAllWithIter('1,,2,,3,,4', ',,')
"
"  "
"  " First test the read-only operations.
"  "
"  call s:Assert(MvStrIndexOfElement('1,,2,,3,,4,,', ',,', '3'), 6, 'MvStrIndexOfElement with array: 1,,2,,3,,4,, sep: ,, for element 3')
"  call s:Assert(MvStrIndexOfElement('1,,2,,3,,4', ',,', '4'), 9, 'MvStrIndexOfElement with array: 1,,2,,3,,4,, sep: ,, for element 4')
"  call s:Assert(MvStrIndexOfElement('1,,2,,3,,4,,', ',,', '1'), 0, 'MvStrIndexOfElement with array: 1,,2,,3,,4,, sep: ,, for element 1')
"  " Test a fix for a previous identified bug.
"  call s:Assert(MvStrIndexOfElement('11,,1,,2,,3,,', ',,', '1'), 4, 'MvStrIndexOfElement with array: 11,,1,,2,,3,, sep: ,, for element 1')
"
"  call s:Assert(MvStrIndexOfElement('1xxxx2xxx3x4xxxx', 'x\+', '3', 'x'), 9, 'MvStrIndexOfElement with array: 1xxxx2xxx3x4xxxx for element 3')
"  call s:Assert(MvStrIndexOfElement('1xxxx2xxx3x4', 'x\+', '3', 'x'), 9, 'MvStrIndexOfElement with array: 1xxxx2xxx3x4 for element 3')
"  call s:Assert(MvStrIndexOfElement('1xxxx2xxx3x4', 'x\+', '4', 'x'), 11, 'MvStrIndexOfElement with array: 1xxxx2xxx3x4 for element 4')
"  call s:Assert(MvStrIndexOfElement('1xxxx2xxx3x4', 'x\+', '1', 'x'), 0, 'MvStrIndexOfElement with array: 1xxxx2xxx3x4 for element 1')
"  call s:Assert(MvStrIndexOfElement('1xxxx', 'x\+', '1', 'x'), 0, 'MvStrIndexOfElement with array: 1xxxx for element 1')
"  call s:Assert(MvStrIndexOfElement('1', 'x\+', '1', 'x'), 0, 'MvStrIndexOfElement with array: 1 for element 1')
"
"  call s:Assert(MvStrIndexOfPattern('1a,1b,1c,1d,', ',', '.c'), 6, 'MvStrIndexOfPattern with array: 1a,1b,1c,1d, for pattern .c')
"
"  call s:Assert(MvStrIndexOfElementAt('1,,2,,3,,4', ',,', 2), 6, 'MvStrIndexOfElementAt with array: 1,,2,,3,,4,, sep: ,, for index 2')
"  call s:Assert(MvStrIndexOfElementAt('1,,2,,3,,4,,', ',,', 3), 9, 'MvStrIndexOfElementAt with array: 1,,2,,3,,4,, sep: ,, for index 3')
"  call s:Assert(MvStrIndexOfElementAt('1,,2,,3,,4,,', ',,', 0), 0, 'MvStrIndexOfElementAt with array: 1,,2,,3,,4,, sep: ,, for index 0')
"  call s:Assert(MvStrIndexOfElementAt('1,,', ',,', 0), 0, 'MvStrIndexOfElementAt with array: 1,, sep: ,, for index 0')
"  call s:Assert(MvStrIndexOfElementAt('1', ',,', 0), 0, 'MvStrIndexOfElementAt with array: 1 sep: ,, for index 0')
"
"  call s:Assert(MvStrIndexOfElementAt('1xxxx2xxx3x4xxxx', 'x\+', 2, 'x'), 9, 'MvStrIndexOfElementAt with array: 1xxxx2xxx3x4xxxx for index 2')
"  call s:Assert(MvStrIndexOfElementAt('1xxxx2xxx3x4xxxx', 'x\+', 0, 'x'), 0, 'MvStrIndexOfElementAt with array: 1xxxx2xxx3x4xxxx for index 1')
"  call s:Assert(MvStrIndexOfElementAt('1xxxx2xxx3x4xxxx', 'x\+', 3, 'x'), 11, 'MvStrIndexOfElementAt with array: 1xxxx2xxx3x4xxxx for index 3')
"  call s:Assert(MvStrIndexOfElementAt('1xxxx', 'x\+', 0, 'x'), 0, 'MvStrIndexOfElementAt with array: 1xxxx for index 0')
"  call s:Assert(MvStrIndexOfElementAt('1', 'x\+', 0, 'x'), 0, 'MvStrIndexOfElementAt with array: 1 for index 0')
"
"  call s:Assert(MvElementAt('1,,2,,3,,4', ',,', 2), '3', 'MvElementAt with array: 1,,2,,3,,4 sep: ,, for index 2')
"  call s:Assert(MvElementAt('1,,2,,3,,4', ',,', 0), '1', 'MvElementAt with array: 1,,2,,3,,4 sep: ,, for index 0')
"
"  call s:Assert(MvElementAt('1xxxx2xxx3x4xxxx', 'x\+', 2, 'x'), '3', 'MvElementAt with array: 1xxxx2xxx3x4xxxx for index 2')
"  call s:Assert(MvElementAt('1xxxx2xxx3x4', 'x\+', 0, 'x'), '1', 'MvElementAt with array: 1xxxx2xxx3x4 for index 0')
"  call s:Assert(MvElementAt('1xxxx', 'x\+', 0, 'x'), '1', 'MvElementAt with array: 1xxxx for index 0')
"  call s:Assert(MvElementAt('1', 'x\+', 0, 'x'), '1', 'MvElementAt with array: 1 for index 0')
"
"  call s:Assert(MvIndexOfElement('1,,2,,3,,4', ',,', '3'), 2, 'MvIndexOfElement with array: 1,,2,,3,,4 sep: ,, for element 3')
"  call s:Assert(MvIndexOfElement('1,,2,,3,,4,,', ',,', '1'), 0, 'MvIndexOfElement with array: 1,,2,,3,,4,, sep: ,, for element 0')
"
"  call s:Assert(MvIndexOfElement('1xxxx2xxx3x4xxxx', 'x\+', '3', 'x'), 2, 'MvIndexOfElement with array: 1xxxx2xxx3x4xxxx for element 3')
"  call s:Assert(MvIndexOfElement('1xxxx2xxx3x4', 'x\+', '4', 'x'), 3, 'MvIndexOfElement with array: 1xxxx2xxx3x4 for element 4')
"  call s:Assert(MvIndexOfElement('1xxxx', 'x\+', '1', 'x'), 0, 'MvIndexOfElement with array: 1xxxx for element 1')
"  call s:Assert(MvIndexOfElement('1', 'x\+', '1', 'x'), 0, 'MvIndexOfElement with array: 1 for element 1')
"
"  call s:Assert(MvIndexOfPattern('1a,1b,1c,1d,', ',', '.c'), 2, 'MvIndexOfPattern with array: 1a,1b,1c,1d, for pattern .c')
"
"  call s:Assert(MvNumberOfElements('1,,2,,3,,4', ',,'), 4, 'MvNumberOfElements with array: 1,,2,,3,,4 sep: ,,')
"  call s:Assert(MvNumberOfElements('1,,2,,3,,4', ',,'), 4, 'MvNumberOfElements with array: 1,,2,,3,,4 sep: ,,')
"  call s:Assert(MvNumberOfElements('1,,', ',,'), 1, 'MvNumberOfElements with array: 1,, sep: ,,')
"  call s:Assert(MvNumberOfElements('1', ',,'), 1, 'MvNumberOfElements with array: 1 sep: ,,')
"
"  call s:Assert(MvNumberOfElements('1xxxx2xxx3x4xxxx', 'x\+'), 4, 'MvNumberOfElements with array: 1xxxx2xxx3x4xxxx')
"  call s:Assert(MvNumberOfElements('1xxxx2xxx3x4', 'x\+'), 4, 'MvNumberOfElements with array: 1xxxx2xxx3x4')
"  call s:Assert(MvNumberOfElements('1xxxx', 'x\+'), 1, 'MvNumberOfElements with array: 1xxxx')
"  call s:Assert(MvNumberOfElements('1', 'x\+'), 1, 'MvNumberOfElements with array: 1')
"
"  call s:Assert(MvContainsElement('1,,2,,3,,4', ',,', '3'), 1, 'MvContainsElement with array: 1,,2,,3,,4 sep: ,, for element 3')
"  call s:Assert(MvContainsElement('1,,2,,3,,4,,', ',,', '1'), 1, 'MvContainsElement with array: 1,,2,,3,,4,, sep: ,, for element 1')
"  call s:Assert(MvContainsElement('1,,2,,3,,4,,', ',,', '0'), 0, 'MvContainsElement with array: 1,,2,,3,,4,, sep: ,, for element 0')
"
"  call s:Assert(MvContainsElement('1xxxx2xxx3x4xxxx', 'x\+', '3', 'x'), 1, 'MvContainsElement with array: 1xxxx2xxx3x4xxxx for element 3')
"  call s:Assert(MvContainsElement('1xxxx2xxx3x4', 'x\+', '4', 'x'), 1, 'MvContainsElement with array: 1xxxx2xxx3x4 for element 4')
"  call s:Assert(MvContainsElement('1xxxx', 'x\+', '1', 'x'), 1, 'MvContainsElement with array: 1xxxx for element 1')
"  call s:Assert(MvContainsElement('1', 'x\+', '1', 'x'), 1, 'MvContainsElement with array: 1 for element 1')
"
"  call s:Assert(MvLastElement('1,,2,,3,,4', ',,'), '4', 'MvLastElement with array: 1,,2,,3,,4 sep: ,,')
"  call s:Assert(MvLastElement('1,,2,,3,,4,,', ',,'), '4', 'MvLastElement with array: 1,,2,,3,,4,, sep: ,,')
"
"  call s:Assert(MvLastElement('1xxxx2xxx3x4xxxx', 'x\+', 'x'), '4', 'MvLastElement with array: 1xxxx2xxx3x4xxxx')
"  call s:Assert(MvLastElement('1xxxx2xxx3x4', 'x\+', 'x'), '4', 'MvLastElement with array: 1xxxx2xxx3x4')
"  call s:Assert(MvLastElement('1xxxx', 'x\+', 'x'), '1', 'MvLastElement with array: 1xxxx')
"  call s:Assert(MvLastElement('1', 'x\+', 'x'), '1', 'MvLastElement with array: 1')
"
"  "
"  " Now test the write operations.
"  "
"  call s:Assert(MvAddElement('1,,2,,3,,4', ',,', '5'), '1,,2,,3,,4,,5,,', 'MvAddElement with array: 1,,2,,3,,4 sep: ,, for element 5')
"  call s:Assert(MvAddElement('1,,2,,3,,4,,', ',,', '5'), '1,,2,,3,,4,,5,,', 'MvAddElement with array: 1,,2,,3,,4,, sep: ,, for element 5')
"
"  call s:Assert(MvAddElement('1,,,2,,,,3,,4', ',\+', '5', ','), '1,,,2,,,,3,,4,5,', 'MvAddElement with array: 1,,,2,,,,3,,4  sep: ,\+ for element 5')
"
"  call s:Assert(MvRemoveElement('1,,2,,3,,4', ',,', '3'), '1,,2,,4,,', 'MvRemoveElement with array: 1,,2,,3,,4 sep: ,, for element 3')
"  call s:Assert(MvRemoveElement('1,,2,,3,,4,,', ',,', '1'), '2,,3,,4,,', 'MvRemoveElement with array: 1,,2,,3,,4,, sep: ,, for element 1')
"
"  call s:Assert(MvRemoveElement('1,,,2,,,,3,,4', ',\+', '2', ','), '1,,,3,,4,', 'MvRemoveElement with array: 1,,,2,,,,3,,4  sep: ,\+ for element 2')
"
"  call s:Assert(MvRemoveElementAt('1,,2,,3,,4', ',,', 2), '1,,2,,4,,', 'MvRemoveElementAt with array: 1,,2,,3,,4 sep: ,, for index 2')
"  call s:Assert(MvRemoveElementAt('1,,2,,3,,4,,', ',,', 0), '2,,3,,4,,', 'MvRemoveElementAt with array: 1,,2,,3,,4,, sep: ,, for index 0')
"
"  call s:Assert(MvRemoveElementAt('1,,,2,,,,3,,4', ',\+', 2, ','), '1,,,2,,,,4,', 'MvRemoveElementAt with array: 1,,,2,,,,3,,4  sep: ,\+ for index 2')
"
"  call s:Assert(MvPushToFront('1,,2,,3,,4', ',,', '3'), '3,,1,,2,,4,,', 'MvPushToFront with array: 1,,2,,3,,4 sep: ,, for element 3')
"  call s:Assert(MvPushToFront('1,,2,,3,,4,,', ',,', '4'), '4,,1,,2,,3,,', 'MvPushToFront with array: 1,,2,,3,,4,, sep: ,, for element 4')
"
"  call s:Assert(MvPushToFront('1,,,2,,,,3,,4', ',\+', '2', ','), '2,1,,,3,,4,', 'MvPushToFront with array: 1,,,2,,,,3,,4  sep: ,\+ for element 2')
"
"  call s:Assert(MvPushToFrontElementAt('1,,2,,3,,4', ',,', 2), '3,,1,,2,,4,,', 'MvPushToFrontElementAt with array: 1,,2,,3,,4 sep: ,, for index 2')
"  call s:Assert(MvPushToFrontElementAt('1,,2,,3,,4,,', ',,', 3), '4,,1,,2,,3,,', 'MvPushToFrontElementAt with array: 1,,2,,3,,4,, sep: ,, for index 3')
"
"  call s:Assert(MvPushToFrontElementAt('1,,,2,,,,3,,4', ',\+', 2, ','), '3,1,,,2,,,,4,', 'MvPushToFrontElementAt with array: 1,,,2,,,,3,,4  sep: ,\+ for index 2')
"  call s:Assert(MvPushToFrontElementAt('1,2\,3,4,5', '\\\@<!\%(\\\\\)*,', 1, ','), '2\,3,1,4,5,', 'MvPushToFrontElementAt with array: 1,2\,3,4,5  sep: ,\+ for index 2')
"
"  call s:Assert(MvPullToBack('1,,2,,3,,4', ',,', '3'), '1,,2,,4,,3,,', 'MvPullToBack with array: 1,,2,,3,,4 sep: ,, for element 3')
"  call s:Assert(MvPullToBack('1,,2,,3,,4,,', ',,', '1'), '2,,3,,4,,1,,', 'MvPullToBack with array: 1,,2,,3,,4,, sep: ,, for element 1')
"
"  call s:Assert(MvPullToBack('1,,,2,,,,3,,4', ',\+', '2', ','), '1,,,3,,4,2,', 'MvPullToBack with array: 1,,,2,,,,3,,4  sep: ,\+ for element 2')
"
"  call s:Assert(MvPullToBackElementAt('1,,2,,3,,4', ',,', 2), '1,,2,,4,,3,,', 'MvPullToBackElementAt with array: 1,,2,,3,,4 sep: ,, for index 2')
"  call s:Assert(MvPullToBackElementAt('1,,2,,3,,4', ',,', 0), '2,,3,,4,,1,,', 'MvPullToBackElementAt with array: 1,,2,,3,,4 sep: ,, for index 0')
"
"  call s:Assert(MvPullToBackElementAt('1,2\,3,4,5', '\\\@<!\%(\\\\\)*,', 1, ','), '1,4,5,2\,3,', 'MvPullToBackElementAt with array: 1,2\,3,4,5  sep: ,\+ for index 2')
"
"  call s:Assert(s:EnsureTrailingSeparator('1,,2,,3,,4,,', ',,'), '1,,2,,3,,4,,', 's:EnsureTrailingSeparator with array: 1,,2,,3,,4,, sep: ,,')
"  call s:Assert(s:EnsureTrailingSeparator('1,,2,,3,,4', ',,'), '1,,2,,3,,4,,', 's:EnsureTrailingSeparator with array: 1,,2,,3,,4 sep: ,,')
"
"  call s:Assert(s:EnsureTrailingSeparator('1,2\,3,4,5', '\\\@<!\%(\\\\\)*,', ','), '1,2\,3,4,5,', 's:EnsureTrailingSeparator with array: 1,2\,3,4,5,  sep: \\\@<!\%(\\\\\)*,')
"
"  call s:Assert(MvInsertElementAt('1,,2,,3,,4', ',,', '5', 2), '1,,2,,5,,3,,4,,', 'MvInsertElementAt with array: 1,,2,,3,,4 sep: ,, for element 5 at index 2')
"  call s:Assert(MvInsertElementAt('1,,2,,3,,4,,', ',,', '5', 0), '5,,1,,2,,3,,4,,', 'MvInsertElementAt with array: 1,,2,,3,,4,, sep: ,, for element 5 at index 0')
"
"  call s:Assert(MvInsertElementAt('1,2\,3,4,5', '\\\@<!\%(\\\\\)*,', '6', 2, ','), '1,2\,3,6,4,5,', 'MvInsertElementAt with array: 1,2\,3,4,5  sep: ,\+ for element 6 at index 2')
"
"  call s:Assert(MvRotateLeftAt('1,,2,,3,,4', ',,', 1), '2,,3,,4,,1,,', 'MvRotateLeftAt with array: 1,,2,,3,,4 sep: ,, at index 1')
"  call s:Assert(MvRotateLeftAt('1,,2,,3,,4', ',,', 0), '1,,2,,3,,4', 'MvRotateLeftAt with array: 1,,2,,3,,4 sep: ,, at index 0')
"  call s:Assert(MvRotateLeftAt('1,,2,,3,,4', ',,', 3), '4,,1,,2,,3,,', 'MvRotateLeftAt with array: 1,,2,,3,,4 sep: ,, at index 3')
"  call s:Assert(MvRotateLeftAt('1,,2,,3,,4', ',,', 4), '1,,2,,3,,4,,', 'MvRotateLeftAt with array: 1,,2,,3,,4 sep: ,, at index 4')
"
"  call s:Assert(MvRotateLeftAt('1,,,2,,,,3,,4', ',\+', '1', ','), '2,,,,3,,4,1,,,', 'MvRotateLeftAt with array: 1,,,2,,,,3,,4  sep: ,\+ at index 1')
"
"  call s:Assert(MvRotateRightAt('1,,2,,3,,4', ',,', 1), '3,,4,,1,,2,,', 'MvRotateRightAt with array: 1,,2,,3,,4 sep: ,, at index 1')
"  call s:Assert(MvRotateRightAt('1,,2,,3,,4', ',,', 0), '2,,3,,4,,1,,', 'MvRotateRightAt with array: 1,,2,,3,,4 sep: ,, at index 0')
"  call s:Assert(MvRotateRightAt('1,,2,,3,,4', ',,', 3), '1,,2,,3,,4,,', 'MvRotateRightAt with array: 1,,2,,3,,4 sep: ,, at index 3')
"  call s:Assert(MvRotateRightAt('1,,2,,3,,4', ',,', 4), '1,,2,,3,,4,,', 'MvRotateRightAt with array: 1,,2,,3,,4 sep: ,, at index 4')
"
"  call s:Assert(MvRotateRightAt('1,,,2,,,,3,,4', ',\+', '1', ','), '3,,4,1,,,2,,,,', 'MvRotateRightAt with array: 1,,,2,,,,3,,4  sep: ,\+ at index 1')
"
"  call s:Assert(MvPromptForElement('a,,b,,c,,d,,', ',,', 'c', 'Please press Enter:', '', 0), 'c', 'MvPromptForElement with array a,,b,,c,,d,, for default element c')
"  call s:Assert(MvPromptForElement2('1,,,2,,,,3,,4', ',\+', 1, 'Please press Enter:', '', 0, 2, ','), '2', 'MvPromptForElement with array a,,b,,c,,d,, for default index 1')
"
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 1, 3), '1,4,3,2,5,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 1 and 3')
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 3, 1), '1,4,3,2,5,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 3 and 1')
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 0, 3), '4,2,3,1,5,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 0 and 3')
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 1, 4), '1,5,3,4,2,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 1 and 4')
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 3, 3), '1,2,3,4,5,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 3 and 3')
"  call s:Assert(MvSwapElementsAt('1,2,3,4,5', ',', 3, 4), '1,2,3,5,4,', 'MvSwapElementsAt with array: 1,2,3,4,5 for elements: 3 and 4')
"
"  call s:Assert(MvSwapElementsAt('1,,,2,,,,3,,4', ',\+', 1, 3, ','), '1,,,4,3,,2,', 'MvSwapElementsAt with array 1,,,2,,,,3,,4 for for elements:1 and 3')
"
"  call s:Assert(MvQSortElements('3,4,2,5,7,1,6', ',', 's:CmpByNumber', -1), '7,6,5,4,3,2,1,', 'MvQSortElements with array: 3,4,2,5,7,1,6 with number comparator in descending order')
"  call s:Assert(MvQSortElements('e,a,d,b,f,c,g', ',', 's:CmpByString', 1), 'a,b,c,d,e,f,g,', 'MvQSortElements with array: e,a,d,b,f,c,g with string comparator in ascending order')
"
"  call s:Assert(MvQSortElements('e,,a,,,d,,b,f,,,,c,,g', ',\+', 's:CmpByString', 1, ','), 'a,b,c,d,e,f,g,', 'MvQSortElements with array: e,a,d,b,f,c,g with string comparator in ascending order')
"endfunction
" Testing }}}

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6: fdm=marker
