# ABSTRACT: VimDebug Daemon 
=head1 SYNOPSIS

   use VimDebug::Daemon;
   VimDebug::Daemon->start();

=head1 DESCRIPTION

This module implements a VimDebug daemon.  The daemon manages communication
between one or more clients and their debuggers.  A debugger is spawned for
each client.

=head1 PROTOCOL

TODO: finish this

bob connects to server
server: 'sessionId'
bob:    'create:sessionId:language:command'
server: 'fileName:lineNumber'
...

=head1 POE STATE DIAGRAM

ClientConnected

ClientInput
    |                               __
    v                              v  |
   In -> Translate -> Write --> Read  |
                      |   ^     |  |  |
                      |   |_____|  |__|
                      |   
                      v
                     Out

=cut
package VimDebug::Daemon;

use strict;
use warnings;
use feature qw(say);
use base qw(Class::Accessor::Fast);

use Carp;
use Data::Dumper::Concise;
use POE qw(Component::Server::TCP);

__PACKAGE__->mk_accessors( qw(vimdebug translatedInput) );


# contants
$VimDebug::Daemon::VERSION = "0.39";
$| = 1;

# protocol constants
my $EOR            = "[vimdebug.eor]";       # end of field
my $EOM            = "\r\nvimdebug.eom";     # end of field
my $BAD_CMD        = "bad command";

# connection constants
my $PORT      = "6543";
my $DONE_FILE = ".vdd.done";


=head2 run

=cut
sub run {
   my $self = shift or die;

   $self->vimdebug({});

   POE::Component::Server::TCP->new(
      Port            => $PORT,
      ClientConnected => \&clientConnected,
      ClientInput     => \&clientInput,
      ObjectStates    => [
         $self => {
            In           => 'in',
            Translate    => 'translate',
            Write        => 'write',
            Read         => 'read',
            Out          => 'out',
         },
      ],
   );

   POE::Kernel->run;
}

sub clientConnected {
say ":::::::clientConnected";
   $_[HEAP]{client}->put($_[SESSION]->ID);
}

sub clientInput {
   $_[KERNEL]->yield("In" => @_[ARG0..$#_]);
}

sub in {
   my $self  = $_[OBJECT];
   my $input = $_[ARG0];
say ":::::::in";

   # first connection from vim: spawn the debugger
   #               spawn:sessionId:language:command
   if ($input =~ /^spawn:(.+):(.+):(.+)$/) {
      $self->vimdebug->{$1} = spawn( $2, $3 );
      $_[KERNEL]->yield("Read" => @_[ARG0..$#_]);
say ":::::::first connection";
      return;
   }

   # second vim session asking the first session to stop working
   #               stop:sessionId
   if ($input =~ /^stop:(.+)$/) {
      my $sessionId = $1;
      if (defined $self->vimdebug->{$sessionId}) {
         $self->vimdebug->{$sessionId}->{stop} = 1;
         $_[KERNEL]->yield("shutdown");
say ":::::::another connection";
         return;
      }
      die "ERROR 003.  Email vimdebug at iijo dot org.";
   }

   # input from current session.  
   $_[KERNEL]->yield("Translate" => @_[ARG0..$#_]);
}

sub spawn {
   my $language = shift or die;
   my $command  = shift or die;

   # load module
   my $moduleName = "VimDebug/${language}.pm";
   require $moduleName;

   # create debugger object
   my $debuggerName = 'VimDebug::' . ${language};
   my $v = eval $debuggerName . "->new();";
   die "no such module exists: $debuggerName: $@" unless defined $v;

   my @cmd = split(/\s+/, $command);
   $v->dbgrCmd(\@cmd);
   $v->start();

   return $v;
}

sub translate {
   my $self = $_[OBJECT];
   my $v    = $self->vimdebug->{$_[SESSION]->ID};
   my $in   = $_[ARG0];
say ":::::::::translate: $in";
   my $cmds;

   # translate protocol $in to native debugger @cmds
   if    ($in =~ /^break:(\d+):(.+)$/) {$cmds = $v->setBreakPoint($1, $2)  }
   elsif ($in =~ /^clear:(\d+):(.+)$/) {$cmds = $v->clearBreakPoint($1, $2)}
   elsif ($in =~ /^clearAll$/        ) {$cmds = $v->clearAllBreakPoints()  }
   elsif ($in =~ /^print:(.+)$/      ) {$cmds = $v->printExpression($1)    }
   elsif ($in =~ /^command:(.+)$/    ) {$cmds = $v->command($1)            }
   elsif ($in =~ /^quit$/            ) {$cmds = $v->quit($1);              }
   elsif ($in =~ /^(\w+):(.+)$/      ) {$cmds = $v->$1($2)                 }
#   elsif ($in =~ /^(\w+)$/           ) {$cmds = $v->$1()                   }
   else  { die "ERROR 002.  Please email vimdebug at iijo dot org.\n"      }

print Dumper $cmds;
   $v->translatedInput($cmds);
   $_[KERNEL]->yield("Write", @_[ARG0..$#_]);
}

sub write {
say "::::::write";
   my $self = $_[OBJECT];
   my $in   = $_[ARG0];
   my $v    = $self->vimdebug->{$_[SESSION]->ID};
   my $cmds = $v->translatedInput();

   if (scalar(@$cmds) == 0) {
      $_[KERNEL]->yield("Out" => @_[ARG0..$#_]);
   }
   else {
      my $c = pop @$cmds;
      $v->write($c);
      if ($in eq 'quit') {
         $v->dbgr->finish();
         $_[KERNEL]->yield("shutdown");
      }
      $_[KERNEL]->yield("Read" => @_[ARG0..$#_]);
   }

   return;
}

sub read {
   my $self = $_[OBJECT];
   my $v    = $self->vimdebug->{$_[SESSION]->ID};
   $v->read(@_)
       ?  $_[KERNEL]->yield("Write" => @_[ARG0..$#_])
       :  $_[KERNEL]->yield("Read"  => @_[ARG0..$#_]);
}

sub out {
   my $self = $_[OBJECT];
   my $v    = $self->vimdebug->{$_[SESSION]->ID};
   my $out;

   if (defined $v->lineNumber and defined $v->filePath) {
      $out = $v->status     . $EOR .
             $v->lineNumber . $EOR .
             $v->filePath   . $EOR .
             $v->out        . $EOM;
   }
   else {
      $out = $v->status . $EOR . $EOR . $EOR . $v->out . $EOM;
   }

   $self->touch();
   $_[HEAP]{client}->put($out);
}

sub touch {
   my $self = shift or die;
   open(FILE, ">", $DONE_FILE);
   print FILE "\n";
   close(FILE);
}

1;
