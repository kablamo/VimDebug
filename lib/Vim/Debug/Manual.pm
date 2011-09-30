# ABSTRACT: What is Vim::Debug and how do I use it?

=head1 DESCRIPTION

The Vim::Debug project integrates the Perl debugger with Vim, allowing
developers to visually step through their code and examine variables.  

Please note that this code is in beta and the underlying Perl libraries will
be changing radically in the near future.


=head1 PREREQUISITES

Vim compiled with +signs and +perl.


=head1 INSTALL INSTRUCTIONS

=head2 With cpanm

    TODO

=head2 With github

    git clone git@github.com:kablamo/VimDebug.git
    cd VimDebug
    perl Makefile.PL
    make
    sudo make install
    cp -r vim/* $VIMHOME/

Replace $VIMHOME with your vim configuration directory.  (/home/username/.vim on unix.)


head1 KEY BINDINGS

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


head1 DEVELOPERS

Fork it on github: http://github.com/kablamo/VimDebug

=cut

package Vim::Debug::Manual;
