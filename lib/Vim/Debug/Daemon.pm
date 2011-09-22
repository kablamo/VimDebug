# ABSTRACT: Handle communication between a debugger and clients

=head1 SYNOPSIS

   use Vim::Debug::Daemon;
   Vim::Debug::Daemon->run;


=head1 DESCRIPTION

This module implements a Vim::Debug daemon.  The daemon manages communication
between one or more clients and their debuggers.  Clients will usually be an
editor like Vim.  A debugger is spawned for each client.  

Internally this is implemented with POE and does non blocking reads for
debugger output.


=head1 COMMUNICATION PROTOCOL

All messages passed between the client (vim) and the daemon (vdd) consist of a
set of fields followed by an End Of Message string.  Each field is seperated
from the next by an End Of Record string.

All messages to the client have the following format:

    Debugger status
    End Of Record
    Line Number
    End Of Record
    File Name
    End Of Record
    Value
    End Of Record
    Debugger output
    End Of Message

All messages to the server have the following format:

    Action (eg step, next, break, ...)
    End Of Record
    Parameter 1
    End Of Record
    Parameter 2
    End Of Record
    ..
    Parameter n 
    End Of Message

After every message, the daemon also touches a file.  Which is kind of crazy.


=head2 Connecting

When you connect to the Vim::Debug Daemon (vdd), it will send you a message
that looks like this:

    $CONNECT . $EOR . $EOR . $EOR . $SESSION_ID . $EOR . $EOM 

You should respond with a message that looks like

    'create' . $EOR . $SESSION_ID . $EOR . $LANGUAGE $EOR $DBGR_COMMAND $EOM

=head2 Disconnecting

To disconnect send a 'quit' message.

    'quit' . $EOM

The server will respond with:

    $DISCONNECT . $EOR . $EOR . $EOR . $EOR . $EOM

And then exit.


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

package Vim::Debug::Daemon;

use Data::Dumper::Concise;
use Moose;
use POE qw(Component::Server::TCP);
use Vim::Debug;

# constants
$| = 1;

# protocol constants
my $EOR            = "[vimdebug.eor]";       # end of field
my $EOM            = "\r\nvimdebug.eom";     # end of field
my $BAD_CMD        = "bad command";
my $CONNECT        = "CONNECT";
my $DISCONNECT     = "DISCONNECT";

# connection constants
my $PORT      = "6543";
my $DONE_FILE = ".vdd.done";

# global var
my $shutdown = 0;

has vimdebug => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has translatedInput => ( is => 'rw', isa => 'Str' );


sub run {
   my $self = shift or die;

   POE::Component::Server::TCP->new(
      Port               => $PORT,
      ClientConnected    => \&clientConnected,
      ClientDisconnected => \&clientDisconnected,
      ClientInput        => \&clientInput,
      ClientError        => \&clientError,
      ObjectStates       => [
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
   wait();
}

sub clientConnected {
   $_[HEAP]{client}->put(
      $CONNECT . $EOR . $EOR . $EOR . $_[SESSION]->ID . $EOR . $EOM 
   );
   touch();
#  $_[SESSION]->option(trace => 1, debug => 1);
}

sub clientDisconnected {
    if ( $shutdown ) {
        $shutdown = 0;
        exit;
    }
}

sub clientError {
    warn "ClientError: " . $_[SESSION]->ID . "\n";
}

sub clientInput {
   $_[KERNEL]->yield("In" => @_[ARG0..$#_]);
}

sub in {
   my $self  = $_[OBJECT];
   my $input = $_[ARG0];

   # first connection from vim: spawn the debugger
   #               start:sessionId:language:command
   if ($input =~ /^start:(.+):(.+):(.+)$/) {
      $self->vimdebug->{$1} = start( $2, $3 );
      $_[KERNEL]->yield("Read" => @_[ARG0..$#_]);
      return;
   }

   # second vim session asking the first session to stop working
   #               stop:sessionId
   if ($input =~ /^stop:(.+)$/) {
      my $sessionId = $1;
      if (defined $self->vimdebug->{$sessionId}) {
         $self->vimdebug->{$sessionId}->stop(1);
         $_[HEAP]{client}->event(FlushedEvent => "shutdown");
         $_[HEAP]{client}->put($DISCONNECT . $EOR . $EOR . $EOR . $EOR . $EOM);
         $self->touch;
         return;
      }
      die "ERROR 003.  Email vimdebug at iijo dot org.";
   }

   # input from current session.  
   $_[KERNEL]->yield("Translate" => @_[ARG0..$#_]);
}

sub start {
    my $language = shift or die;
    my $command  = shift or die;

    my @cmd = split(/\s+/, $command);
    my $v = Vim::Debug->new(language => $language, invoke => \@cmd);
    $v->start();

    return $v;
}

sub translate {
   my $self = $_[OBJECT];
   my $v    = $self->vimdebug->{$_[SESSION]->ID};
   my $in   = $_[ARG0];

   # Translate protocol $in to native debugger cmds. 
   $v->translatedInput([$v->translate($in)]);

   $_[KERNEL]->yield("Write", @_[ARG0..$#_]);
}

sub write {
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

      chomp($in);
      if ($in eq 'quit') {
         $v->finish; # makes sure the child process exits
         $shutdown = 1;
         $_[HEAP]{client}->event(FlushedEvent => "shutdown");
         $_[HEAP]{client}->put($DISCONNECT . $EOR . $EOR . $EOR . $EOR . $EOM);
         return;
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
             $v->value      . $EOR .
             $v->out        . $EOM;
   }
   else {
      $out = $v->status . $EOR . $EOR . $EOR . $EOR . $v->out . $EOM;
   }

   $_[HEAP]{client}->put($out);
   $self->touch;
}

sub touch {
   open(FILE, ">", $DONE_FILE);
   print FILE "\n";
   close(FILE);
}

1;
