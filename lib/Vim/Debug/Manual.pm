# ABSTRACT: Integrate the Perl debugger with Vim

=head1 What is VimDebug?

VimDebug integrates the Perl debugger with Vim, allowing developers to
visually step through their code, examine variables, set or clear
breakpoints, etc.

VimDebug is known to work under Unix/Ubuntu/OSX. It requires Perl 5.FIXME or
later and some CPAN modules may need to be installed.  It also requires Vim
7.FIXME or later that was built with the +signs and +perl extensions.

=head1 How do I install VimDebug?

VimDebug has a Perl component and a Vim component.

A simple way to install the Perl component is to use
L<cpanminus's|https://metacpan.org/module/App::cpanminus> C<cpanm>
program. First, install C<cpanminus>:

    curl -L http://cpanmin.us | perl - --sudo App::cpanminus

Then, install VimDebug's Perl files:

    cpanm Vim::Debug

Next, install the Vim component, by executing the following program,
supplied by the Perl component:

    vimdebug-install -d ~/.vim

You may want to replace C<~/.vim> by some other directory that your
Vim recognizes as a runtimepath directory. See Vim's ":help
'runtimepath'" for more information.

Finally, install and read the Vim help file, which describes
VimDebug's keymap:

    :helptags ~/.vim/doc
    :help VimDebug

Make sure that the directory where that C<doc> directory resides is in
your Vim runtimepath, else Vim won't find its help information even if
it manages to build the help index.

=head1 Using VimDebug

Launch Vim and open a file named with a ".pl" extension. Press <F12>
to start the debugger. To change the default Vim key bindings, shown
here, edit VimDebug.vim:

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

=head1 Improving VimDebug

VimDebug is on github: https://github.com/kablamo/VimDebug.git

To do development work on VimDebug, clone its git repo and read
./documentation/DEVELOPER.HOWOTO.

In principle, the VimDebug code can be extended to handle other
debuggers, like the one for Ruby or Python, but that remains to be
done.

Please note that this code is in beta.

=cut

package Vim::Debug::Manual;

# VERSION

