# ABSTRACT: Integrate the Perl debugger with Vim
package Vim::Debug::Manual;
# VERSION

=head1 What is VimDebug

VimDebug allows you to launch the Perl debugger (*1) on some file that
you have opened in Vim and to visually step through your code, set
breakpoints, examine variables, etc.

VimDebug is known to work under Unix/Ubuntu/OSX. It is implemented as
a Perl module, Vim::Debug, that comes with some Vim add-on files.

=head1 Installation requirements

You will need a Vim 7.3 or later that was built with at least the
+perl, +signs, and +autoload extensions.

The compiled in +perl extension will be used to run the Vim::Debug
files and its dependencies, so make make sure to use this perl when
installing Vim::Debug (you may need to rebuild your Vim to match your
perl if this is not the case).

=head1 Installing VimDebug

First, install the Vim::Debug module and its dependencies from CPAN.
If you're unsure how to do this, it may be as simple as C<cpanm
Vim::Debug> if you first install
L<cpanminus|https://metacpan.org/module/App::cpanminus>.

Vim::Debug comes with some Vim add-on files. It also comes with a
program you should run to install these files and build the help tags
file. For example:

    vimdebug-install -d ~/.vim

You may want to replace C<~/.vim> with some other directory that your
Vim will recognize as a runtimepath directory. See Vim's C<:help
'runtimepath'> for more information.

Again, note that the perl that will be executing that command should
be the same as the one used for the Vim instance's +perl extension,
otherwise, you may end up using the wrong version of VimDebug's Vim
add-ons.

Once installed, launch Vim and read ':help VimDebug'.

=head1 Improving VimDebug

Read the git repo's ./documentation/DEVELOPER file, repo which you can
clone from L<https://github.com/kablamo/VimDebug.git>.

(*1) In principle, the VimDebug code can be extended to handle other
debuggers, like Ruby's or Python's, but that remains to be done.

Please note that this code is in beta.

=cut

