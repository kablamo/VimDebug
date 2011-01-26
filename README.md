VIMDEBUG
========

Integrates your language's debugger with Vim.  Currently there is support for
Perl, Ruby, and Gdb.  Please note that this code very much in beta and is
still missing some important capabilities.


## REQUIREMENTS ##

Perl 5.6.0+
a small number of Perl modules
Vim with +signs compiled in.



## HOW TO INSTALL VIMDEBUG ##

    tar xvzf VimDebug*.tar.gz
    cd VimDebug*
    perl Makefile.PL
    make
    sudo make install
    cp -r vim/* $VIMHOME/



## HOW TO INSTALL PERL MODULES ##

Perl modules are easily installed using cpanm.  If you don't have cpanm, this
is the simplest way to get it:

    curl -L http://cpanmin.us | perl - --sudo App::cpanminus

Then just type:

    sudo cpanm IO::Pty
    sudo cpanm IPC::Run

For more help see:
http://search.cpan.org/~miyagawa/App-cpanminus-1.1007/lib/App/cpanminus.pm



## USAGE ##


If you want to customize these keymappings, edit VimDebug.vim:

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


