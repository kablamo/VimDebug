# VIMDEBUG

VimDebug integrates the Perl debugger with Vim.  


### Requirements

 - Unix/Ubuntu/OSX
 - Vim with +signs, and +perl compiled in
 - Perl 5.6.0+
 - The Vim::Debug Perl module


### Install instructions

Perl modules are easily installed using cpanm.  If you don't have cpanm, this
is the simplest way to get it:

    curl -L http://cpanmin.us | perl - --sudo App::cpanminus

To install Vim::Debug:

    sudo cpanm Vim::Debug

For more help installing Perl modules, see the [cpanm documentation][1]


### VimDebug key bindings

These are the default key bindings.  To change them, edit VimDebug.vim:

    <F12>      Start the debugger
    <Leader>s/ Start the debugger.  Prompts for command line arguments.
    <F10>      Restart debugger. Break points are ALWAYS saved (for all dbgrs).
    <F11>      Exit the debugger

    <F6>       Next
    <F7>       Step
    <F8>       Continue

    <Leader>b  Set break point on the current line
    <Leader>c  Clear break point on the current line

    <Leader>v  Print the value of the variable under the cursor
    <Leader>v/ Print the value of an expression thats entered

    <Leader>/  Type a command for the debugger to execute and echo the result



[1]: http://search.cpan.org/~miyagawa/App-cpanminus-1.1007/lib/App/cpanminus.pm
