=head1 NAME

VimDebug::DebuggerInterface::Base - a base class for VimDebug::DebuggerInterface::* modules

=head1 VERSION

$Id: Debugger.pm 93 2007-12-22 21:05:20Z eric $

=head1 SYNOPSIS

   package VimDebug::DebuggerInterface::Perl;

   use IPC::Run qw(start pump finish timeout);
   use VimDebug::DebuggerInterface::Base qw(
     $COMPILER_ERROR
     $RUNTIME_ERROR
     $APP_EXITED
     $LINE_INFO
     $DBGR_READY
     $TIME
     $DEBUG
   );

   @ISA = qw(VimDebug::DebuggerInterface::Base);

   use strict;
   use warnings FATAL => all;
   use Carp;

   # Implement all the API methods listed in VimDebug::DebuggerInterface.  The
   # methods in VimDebug::DebuggerInterface::Base may make the developers life
   # simpler.

   sub startDebugger {
      my $self = shift or confess;
      my $path               = shift or die;
      my @commandLineOptions = @_;

      # this regexe aids in parsing debugger output.  it is required.
      $self->dbgrPromptRegex($dbgrPromptRegex);

      $self->SUPER::startDebugger("perl -d $path @commandLineOptions");
      return undef;
   }

   sub next {
      my $self = shift or confess;
      $self->SUPER::command('next'); # where 'next' is the command accepted by
                                     # the debugger in your chosen language.
      return undef;
   }

   # ...etc
   

=head1 DESCRIPTION

This module extends VimDebug::DebuggerInterface.  It is a helper clase for
developers who wish to implement the VimDebug::DebuggerInterface for the
language of their choice. 

=cut

package VimDebug::DebuggerInterface::Base;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use IPC::Run qw(start pump finish timeout);
use base qw(VimDebug::DebuggerInterface);

our $TIME           = 5;
our $DEBUG          = 0;
our $READ;
our $WRITE;

my @ATTRIBUTES     = (qw(
   _timeout 
   dbgr 

   lineNumber 
   filePath
   dbgrPromptRegex
));

# build getters/setters for encapsulation
for my $field (@ATTRIBUTES) {
    my $slot = __PACKAGE__ . "::$field";
    no strict "refs";          # So symbolic ref to typeglob works.

    *$field = sub {
        my $self = shift;
        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

=head1 HELPER METHODS

The following methods may (or may not) be useful.  They are only a suggestion.
Note that almost all commands cause debuggers to print a response of some kind
to the terminal.  This output is captured and can be retrieved via the method
output() listed below.

=head2 _startDebugger($debuggerInvocation)

$debuggerInvocation is the command used to invoke the debugger.  

Returns undef (this is subject to change)
=cut
sub _startDebugger {
   my $self        = shift or confess;
   my $incantation = shift or confess;
   my $output;

   $self->_timeout(timeout($TIME));
   $self->dbgr(
      start($incantation, 
            '<pty<', \$WRITE,
            '>pty>', \$READ,
            $self->_timeout));

   $self->getUntilPrompt();
   $self->parseOutput($self->output);

   return undef;
}

=head2 _command($command)

Returns a string
=cut
sub _command {
   my $self = shift or die;
   my $command = shift or die;

   # write
   $WRITE .= "$command\n";

   # read
   $self->getUntilPrompt();

   # parse output
   my $output = $self->output;
   $self->parseOutput($output);
   my $prompt = $self->dbgrPromptRegex;
   $output =~ s/$prompt//os;
   return $output;
}

=head2 _quit($command)

Returns undef (this is subject to change)
=cut
sub _quit {
   my $self = shift or confess;
   my $command = shift or confess;

   $WRITE .= "$command\n";
   $self->dbgr->finish();

   return undef;
}

=head2 getUntilPrompt 

Reads output of the child process until the next instance of
$VimDebug::DebuggerInterface::Base::debuggerPrompt is found.

Returns undef (this is subject to change)
=cut
sub getUntilPrompt   {
   my $self   = shift or die;
   my $prompt = $self->dbgrPromptRegex;
   my $output = '';

   $output = $READ; # clear output buffer

   eval {
      $self->dbgr->pump() until $READ =~ /$prompt/s;
   };
   if ($@ =~ /process ended prematurely/ and length($READ) != 0) {
      print "$READ\n" if $DEBUG;
      $self->dbgr->finish();
      undef $@;
   }
   elsif ($@ =~ /process ended prematurely/) {
      print "process ended prematurely\n" if $DEBUG;
      $self->dbgr->finish();
      undef $@;
   }
   elsif ($@) {
      die $@;
   }
   $self->_timeout->reset();
   $output = $READ;
   print "[output][$output]\n" if $DEBUG;
   $READ = '';

   $self->output($output);

   return undef;
}

=head2 output($output)

Remove ornaments (like <CTL-M> or irrelevant error messages or whatever) from
text. 

Returns $output cleansed
=cut
sub output {
   my $self = shift or die;
   my $output = '';

   if (@_) {
      $output = shift;
      $output =~ s///mg;
      $self->{output} = $output;
   }

   return $self->{output};
}

=head2 parseOutput($output)

Parses the string $output.  If possible it sets the filePath() and lineNumber()
attributes.  

Returns undef;
=cut
sub parseOutput {
   my $self   = shift or die;
   my $output = shift or die;

   $self->parseForLineNumber($output);
   $self->parseForFilePath($output);

   return undef;
}

=head2 parseForLineNumber($output)

Parses $output and sets $self->lineNumber($number) if possible.

Returns undef;
=cut
sub parseForLineNumber {
   my $self = shift or die;
   confess "developers should implement this method in their modules";
   return undef;
}

=head2 parseForFilePath($output)

Parses $output and sets $self->filePath($path) if possible.

Returns undef
=cut
sub parseForFilePath {
   my $self = shift or die;
   confess "developers should implement this method in their modules";
   return undef;
}

=head2 lineNumber($number)

If $number parameter is used, the lineNumber class attribute is set using that
value.  If no parameters are passed, the current value of the lineNumber class
attribute is returned.

=head2 filePath($path)

If $path parameter is used, the filePath class attribute is set using that
value.  If no parameters are passed, the current value of the filePath class
attribute is returned.

=head2 dbgrPromptRegex($regex)

If $regex parameter is used, the dbgrPromptRegex class attribute is set using that
value.  If no parameters are passed, the current value of the dbgrPromptRegex class
attribute is returned.


=head1 SEE ALSO

L<Devel::ebug>, L<perldebguts>


=head1 AUTHOR

Eric Johnson, cpan at iijo : :dot: : org

=head1 COPYRIGHT

Copyright (C) 2003 - 3090, Eric Johnson

This module is GPL.

=cut

1;
