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
        
            ---> Stop
           |
    ClientInput ----------> Start
      |                      |   
      |                      |   __
      v                      v  v  |
     Translate --> Write --> Read  |
                   |   ^     |  |  |
                   |   |_____|  |__|
                   |   
                   v
                  Out

=cut

package Vim::Debug::Daemon;

use Moose;
use MooseX::ClassAttribute;
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

class_has debuggers => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub {{}},
);

sub run {
    POE::Component::Server::TCP->new(
        Port               => $PORT,
        ClientConnected    => \&clientConnected,
        ClientDisconnected => \&clientDisconnected,
        ClientInput        => \&clientInput,
        ClientError        => \&clientError,
        InlineStates    => {
            Start     => \&start,
            Stop      => \&stop,
            Translate => \&translate,
            Write     => \&write,
            Read      => \&read,
            Out       => \&out,
            Quit      => \&quit,
        },
    );

    POE::Kernel->run;
    wait();
}

sub clientConnected {
    $_[HEAP]{client}->put(
       $CONNECT . $EOR . $EOR . $EOR . $_[SESSION]->ID . $EOR . $EOM 
    );
    touch();
#   $_[SESSION]->option(trace => 1, debug => 1);
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
    my $state;

       if ($_[ARG0] =~ /^start/) {$state = 'Start'    }
    elsif ($_[ARG0] =~ /^stop/ ) {$state = 'Stop'     }
    else                         {$state = 'Translate'}

    $_[KERNEL]->yield($state => @_[ARG0..$#_]);
}

sub start {
    die 'ERROR 004.  Email vimdebug at iijo dot org.'
        unless $_[ARG0] =~ /^start:(.+):(.+):(.+)$/x;

    my ($sessionId, $language, $command) = ($1, $2, $3);

    __PACKAGE__->debuggers->{$sessionId} = Vim::Debug->new(
        language => $language, 
        invoke   => $command
    );

    $_[HEAP]{debugger}    = __PACKAGE__->debuggers->{$sessionId};
    $_[HEAP]{translation} = [];

    $_[KERNEL]->yield("Read" => @_[ARG0..$#_]);
}

sub stop {
    die 'ERROR 005.  Email vimdebug at iijo dot org.'
        unless $_[ARG0] =~ /^stop:(.+)$/x;

    my $sessionId = $1;

    die 'ERROR 006.  Email vimdebug at iijo dot org.'
        unless defined __PACKAGE__->debuggers->{$sessionId};

    __PACKAGE__->debuggers->{$sessionId}->stop(1);
    $_[HEAP]{client}->event(FlushedEvent => "shutdown");
    $_[HEAP]{client}->put($DISCONNECT . $EOR . $EOR . $EOR . $EOR . $EOM);
    touch();
}

sub translate {
    # Translate protocol $in to native debugger cmds. 
    $_[HEAP]{translation} = $_[HEAP]{debugger}->translate($_[ARG0]);
    $_[KERNEL]->yield("Write", @_[ARG0..$#_]);
}

sub quit {
    $_[HEAP]{debugger}->finish; # makes sure the child process exits;
    $shutdown = 1;
    $_[HEAP]{client}->event(FlushedEvent => "shutdown");
    $_[HEAP]{client}->put($DISCONNECT . $EOR . $EOR . $EOR . $EOR . $EOM);
}

sub write {
    my $input    = $_[ARG0];
    my $debugger = $_[HEAP]{debugger};
    my $cmds     = $_[HEAP]{translation};
    my $state;

    if (scalar(@$cmds) == 0) { 
        $state = 'Out';
    }
    elsif ($input =~ /^quit/  ) {
        $debugger->write(pop @$cmds);
        $state = 'Quit';
    }
    else { 
        $debugger->write(pop @$cmds);
        $state = 'Read';
    }

    $_[KERNEL]->yield($state => @_[ARG0..$#_]);
}

sub read {
   $_[HEAP]{debugger}->read($_[ARG0])
       ?  $_[KERNEL]->yield("Write" => @_[ARG0..$#_])
       :  $_[KERNEL]->yield("Read"  => @_[ARG0..$#_]);
}

sub out {
   my $v = $_[HEAP]{debugger};
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
   touch();
}

sub touch {
   open(FILE, ">", $DONE_FILE);
   print FILE "\n";
   close(FILE);
}


1;
