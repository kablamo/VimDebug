# ABSTRACT: Handle communication between a debugger and clients (DEPRECATED)

=head1 SYNOPSIS

   use Vim::Debug::Daemon;
   Vim::Debug::Daemon->run;

=head1 DESCRIPTION

Please note that this module is deprecated and no longer maintained.

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

This module implements a TCP server.  Clients will usually be an editor like
Vim.  A debugger is spawned for each client.  The daemon manages communication
between one or more clients and their debuggers.

Internally this is implemented with POE so that it can do non blocking reads
for debugger output.  This allows the user to send an interrupt.  This is
useful when, for example, an infinite loop occurs or if something is just
taking a long time.

See L<Vim::Debug::Protocol> for a description of the communication protocol.

=cut
package Vim::Debug::Daemon;

# VERSION

use Moose;
use MooseX::ClassAttribute;
use POE qw(Component::Server::TCP);
use Vim::Debug;
use Vim::Debug::Protocol;

# constants
$| = 1;

# global var
my $shutdown = 0;

class_has port => ( is => 'ro', isa => 'Int', default => 6543 );

class_has debuggers => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub {{}},
);

sub run {
    my $self = shift or die;

    POE::Component::Server::TCP->new(
        Port               => $self->port,
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
    my $response = Vim::Debug::Protocol->connect($_[SESSION]->ID);
    $_[HEAP]{client}->put($response);
    Vim::Debug::Protocol->touch;
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
    )->start;

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
    $_[HEAP]{client}->put(Vim::Debug::Protocol->disconnect);
    Vim::Debug::Protocol->touch;
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
    $_[HEAP]{client}->put(Vim::Debug::Protocol->disconnect);
    Vim::Debug::Protocol->touch;
}

sub write {
    my $cmds = $_[HEAP]{translation};
    my $state;

    if (scalar(@$cmds) == 0) {
        $state = 'Out';
    }
    else {
        $state = $_[ARG0] =~ /^quit/ ? 'Quit' : 'Read';
        $_[HEAP]{debugger}->write(pop @$cmds);
    }
    $_[KERNEL]->yield($state => @_[ARG0..$#_]);
}

sub read {
   $_[HEAP]{debugger}->read($_[ARG0])
       ?  $_[KERNEL]->yield("Write" => @_[ARG0..$#_])
       :  $_[KERNEL]->yield("Read"  => @_[ARG0..$#_]);
}

sub out {
    my $response = Vim::Debug::Protocol->response($_[HEAP]{debugger}->state);
    $_[HEAP]{client}->put($response);
    Vim::Debug::Protocol->touch;
}

1;
