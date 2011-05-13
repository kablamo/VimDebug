# ABSTRACT: VimDebug Daemon 

=head1 SYNOPSIS

   use VimDebug::Daemon;
   VimDebug::Daemon->start(
      language  => 'Perl',
      command   => [qw(perl -d foo.pl)],
   );

=head1 DESCRIPTION

This module implements a VimDebug daemon.  The daemon spawns a debugger and
sends messages back

=cut

package VimDebug::Daemon;

use strict;
use warnings 'FATAL' => 'all';
use feature qw(say);
use Carp;

use POE qw(Component::Server::TCP);

# protocol constants
my $EOR            = "[vimdebug.eor]";       # end of field
my $EOM            = "\r\nvimdebug.eom";     # end of field
my $COMPILER_ERROR = "compiler error";       # not used yet
my $RUNTIME_ERROR  = "runtime error";        # not used yet
my $APP_EXITED     = "application exited";   # not used yet
my $DBGR_READY     = "debugger ready";
my $BAD_CMD        = "bad command";

# connection constants
my $PORT           = "6543";
my $DONE_FILE      = ".vdd.done";

# globals
$VimDebug::Daemon::VERSION = "0.39";
my $dbgr;



=head2 start()

=cut
sub start {
   my $class = shift or die;
   my %params = @_;
   die usage() unless defined $params{language};
   die usage() unless defined $params{command};

   spawnDebugger(@_);

   POE::Component::Server::TCP->new(
      Port            => $PORT,
      ClientConnected => \&ClientConnected,
      ClientInput     => \&ClientInput,
   );

   POE::Kernel->run;
}

sub usage {
   return "
Usage: vdd \$debugger \$command

The vim debugger daemon uses the perl module
VimDebug::DebuggerInterface::\$debugger to invoke
a debugger using the \$command.

Communication with the daemon occurs on port $PORT
";
}

=head2 spawnDebugger()

=cut
sub spawnDebugger {
   my %params = @_ or confess;

   confess "language param is required"  unless defined $params{language};
   confess "command param is required"   unless defined $params{command};

   my $language  = $params{language};
   my $command   = $params{command};

   my $path = "VimDebug/DebuggerInterface/${language}.pm";
   require $path;

   my $module = "VimDebug::DebuggerInterface::${language}";
   $dbgr = $module->new();
   $dbgr->startDebugger(@$command);  # TODO: rename to $debugger->start()

   return undef;
}

=head2 ClientConnected()

=cut
sub ClientConnected {
   reportBack($_[HEAP]{client});
   return undef;
}

=head2 ClientInput()

=cut
sub ClientInput {
   my $cmd = $_[ARG0];
   my $o; # output

   if    ($cmd =~ /^break:(\d+):(.+)$/    ) {$o = $dbgr->setBreakPoint($1, $2)  }
   elsif ($cmd =~ /^clear:(\d+):(.+)$/    ) {$o = $dbgr->clearBreakPoint($1, $2)}
   elsif ($cmd =~ /^clearAll$/            ) {$o = $dbgr->clearAllBreakPoints()  }
   elsif ($cmd =~ /^printExpression:(.+)$/) {$o = $dbgr->printExpression($1)    }
   elsif ($cmd =~ /^command:(.+)$/        ) {$o = $dbgr->command($1)            }
   elsif ($cmd =~ /^quit$/                ) {$o = $dbgr->quit($1); exit         }
   elsif ($cmd =~ /^(\w+):(.+)$/          ) {$o = $dbgr->$1($2)                 }
   elsif ($cmd =~ /^(\w+)$/               ) {$o = $dbgr->$1()                   }
   else  {
      $o = $BAD_CMD . $EOR . $EOR . $EOR . $EOM;
   }

   reportBack($_[HEAP]{client});

   return undef;
}

sub reportBack {
   my $client = shift or die;
   my $o;
   if (defined $dbgr->lineNumber and defined $dbgr->filePath) {
      $o = $DBGR_READY       . $EOR .
           $dbgr->lineNumber . $EOR .
           $dbgr->filePath   . $EOR .
           $dbgr->output     . $EOM;
   }
   else {
      $o = $DBGR_READY . $EOR . $EOR . $EOR . $dbgr->output . $EOM;
   }

   touch();
   $client->put($o);
}

sub touch {
   open(FILE, ">", $DONE_FILE);
   print FILE "\n";
   close(FILE);
}

1;
