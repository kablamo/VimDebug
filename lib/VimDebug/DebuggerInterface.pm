=head1 NAME

VimDebug::DebuggerInterface - Debugger interface to many debuggers

=head1 VERSION

$Id: Debugger.pm 93 2007-12-22 21:05:20Z eric $

=head1 SYNOPSIS

   use VimDebug::DebuggerInterface;
   
   $debugger = VimDebug::DebuggerInterface->new(); 
   $debugger->startDebugger(); 
   if ($debugger->compiler_error) {
      # handle error
   }

   $debugger->step();  # or $debugger->next() or $debugger->continue()
   if ($debugger->runtime_error) {
      # handle error
   }
   elsif ($debugger->finished) {
      # handle this
   }
   $lineNumber = $debugger->lineNumber();
   $filePath   = $debugger->filePath();

   $lineNumber = $debugger->setBreakPoint($aLineNumber, $aFilePath);
   $debugger->clearBreakPoint($aLineNumber, $aFileName);
   $debugger->clearAllBreakPoints();

   $output     = $debugger->printExpression($expression);
   $output     = $debugger->command($command);

   $debugger->restart();
   if ($debugger->compiler_error) {
      # handle error
   }

   $debugger->quit();

=head1 DESCRIPTION

This module details a common interface to the debugger for any language.  An
example use of this project, is a developer who wants to implement a language
agnostic debugger for Vim or Emacs.

The following sections describe this API.

=cut

package VimDebug::DebuggerInterface;
use strict;
use warnings 'FATAL' => 'all';
use Carp;

$VimDebug::DebuggerInterface::VERSION = "0.39";

sub new {
   my $class = shift;
   my $self = {};
   bless $self, $class;
   return $self;
}


=head1 API METHODS

=head2 startDebugger($path, @commandLineOptions)

$path is the path to file to be run in the debugger.
@commandLineOptions are the options to be passed to the program indicated by $path.

Returns undef (this is subject to change)
=cut
sub startDebugger {}

=head2 next()

Returns undef (this is subject to change)
=cut
sub next {}

=head2 step()

Returns undef (this is subject to change)
=cut
sub step {}

=head2 step()

Returns undef (this is subject to change)
=cut
sub cont {}

=head2 setBreakPoint($lineNumber, $fileName)

Returns $lineNumber
=cut
sub setBreakPoint {}

=head2 clearBreakPoint($lineNumber, $fileName)

Returns undef (this is subject to change)
=cut
sub clearBreakPoint {}

=head2 clearAllBreakPoints()

Returns undef (this is subject to change)
=cut
sub clearAllBreakPoints() {}

=head2 printExpression($expression)

Returns a string
=cut
sub printExpression {}

=head2 command($command)

Returns a string
=cut
sub command {}

=head2 restart()

Returns undef (this is subject to change)
=cut
sub restart {}

=head2 quit()

Returns undef (this is subject to change)
=cut
sub quit {}

=head2 lineNumber()

Returns the line number the debugger is currently stopped on
=cut
sub lineNumber() {}

=head2 filePath()

Returns a string containing the path to the file which the debugger is currently stopped in.
=cut
sub filePath() {}

=head2 compilerError()

Returns true if a compiler error occurred.
=cut
sub compilerError() {}

=head2 runtimeError()

Returns true if a runtime error occurred.
=cut
sub runtimeError() {}


=head1 DEVELOPERS 

Developers who want to add support for their favorite language by contributing
a module should read the perldoc for L<VimDebug::DebuggerInterface::Base>. 


=head1 SEE ALSO

L<VimDebug::DebuggerInterface::Base>, L<Devel::ebug>, L<perldebguts>


=head1 AUTHOR

Eric Johnson, cpan at iijo : :dot: : org

=head1 COPYRIGHT

Copyright (C) 2003 - 3090, Eric Johnson

This module is GPL.

=cut

1;
