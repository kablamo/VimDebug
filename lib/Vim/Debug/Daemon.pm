# ABSTRACT: Handle communication between a debugger and a client
package Vim::Debug::Daemon;
# VERSION

=head1 SYNOPSIS

    use Vim::Debug::Daemon;
    my $talker = Vim::Debug::Daemon->start;
    Vim::Debug::Daemon->run;

=head1 DESCRIPTION

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

This module implements a TCP server.  Clients will usually be an
editor like Vim.  A debugger is spawned for each client.  The daemon
manages communication between one or more clients and their debuggers.

Internally this is implemented with POE so that it can do non blocking
reads for debugger output.  This allows the user to send an interrupt.
This is useful when, for example, an infinite loop occurs or if
something is just taking a long time.

=cut
use Moose;
use MooseX::ClassAttribute;
use POE qw(Component::Server::TCP);
use Vim::Debug;
use Vim::Debug::Talker;
use Socket 'unpack_sockaddr_in';
use File::Temp;

class_has _vim_debug => ( is  => 'rw', isa => 'Vim::Debug');
class_has _talker    => ( is  => 'rw', isa => 'Vim::Debug::Talker');

=func start()

Returns a Vim::Debug::Talker reference, to communicate with the daemon
that will be launched by run().

=cut
sub start {
    POE::Component::Server::TCP->new(
        ClientConnected    => \&clientConnected,
        ClientDisconnected => \&clientDisconnected,
        ClientInput        => \&clientInput,
        ClientError        => \&clientError,
        Started => sub {
            __PACKAGE__->_talker(Vim::Debug::Talker->new(
                port      => (unpack_sockaddr_in($_[HEAP]{listener}->getsockname))[0],
                done_file => File::Temp->new,
            ));
        },
        InlineStates => {
            QuitDaemon    => \&quit_daemon,
            StartDbgr     => \&start_dbgr,
            InterruptDbgr => \&interrupt_dbgr,
            StopDbgr      => \&stop_dbgr,
            Translate     => \&translate,
            ReadDbgr      => \&read_dbgr,
            WriteDbgr     => \&write_dbgr,
        },
    );
    return __PACKAGE__->_talker;
}

=func run()

Starts the POE event loop running.

=cut
sub run {
    POE::Kernel->run;
    wait();
}

sub clientConnected {
   # warn "clientConnected\n";
}

sub clientDisconnected {
   # warn "clientDisconnected\n";
}

sub clientInput {
    for my $trigger (
        [qr/^start/       => 'StartDbgr'],
        [qr/^interrupt/   => 'InterruptDbgr'],
        [qr/^stop/        => 'StopDbgr'],
        [qr/^quit_daemon/ => 'QuitDaemon'],
            # Default.
        [qr/./            => 'Translate'],
    ) {
        my ($trig_patt, $trig_state) = @$trigger;
        if ($_[ARG0] =~ $trig_patt) {
            $_[KERNEL]->yield($trig_state => @_[ARG0 .. $#_]);
            last;
        }
    }
}

sub clientError {
    warn "ClientError: " . join(" - ", @_[ARG0 .. $#_]) . "\n";
}

sub quit_daemon {
    exit;
}

sub start_dbgr {
    $_[ARG0] =~ /^start:(.+):(.+):(.*)$/x or do {
        $_[HEAP]{client}->put(
            Vim::Debug::Talker->custom_response({status => 'bad_cmd'})
        );
        __PACKAGE__->_talker->_create_done_file;
        return;
    };

    my ($language, $filename, $arguments) = ($1, $2, $3);
    my $VD = Vim::Debug->new(language => $language);
        # Will be empty string if start() succeeded.
    my $status = $VD->start($filename, $arguments);
    if ($status) {
        $_[HEAP]{client}->put(
            Vim::Debug::Talker->custom_response({status => $status})
        );
        __PACKAGE__->_talker->_create_done_file;
       # return;
    }
    else {
        __PACKAGE__->_vim_debug($VD);
        $_[HEAP]{translation} = [];
    }

    $_[KERNEL]->yield("ReadDbgr" => @_[ARG0..$#_]);
}

sub interrupt_dbgr {
    __PACKAGE__->_vim_debug->interrupt;
}

sub stop_dbgr {
    __PACKAGE__->_vim_debug->stop;
    $_[HEAP]{client}->put(
        Vim::Debug::Talker->custom_response({status => "stopped"})
    );
    __PACKAGE__->_talker->_create_done_file;
}

sub translate {
    my $translated_cmd;
    if (! defined(
        $translated_cmd = __PACKAGE__->_vim_debug->translate($_[ARG0])
    )) {
        $_[HEAP]{client}->put(
            Vim::Debug::Talker->custom_response({status => "bad_cmd"})
        );
        __PACKAGE__->_talker->_create_done_file;
        return;
    }

    $_[HEAP]{translation} = $translated_cmd;
    $_[KERNEL]->yield("WriteDbgr", @_[ARG0..$#_]);
}

sub read_dbgr {
    my $state = "ReadDbgr";
    if (__PACKAGE__->_vim_debug->read) {
        __PACKAGE__->_talker->_create_done_file;
        $state = "WriteDbgr";
    }
    $_[KERNEL]->yield($state, @_[ARG0 .. $#_]);
}

sub write_dbgr {
    my $cmds = $_[HEAP]{translation};

    if (@$cmds == 0) {
        $_[HEAP]{client}->put(
            Vim::Debug::Talker->response(__PACKAGE__->_vim_debug)
        );
        __PACKAGE__->_talker->_create_done_file;
    }
    else {
        __PACKAGE__->_vim_debug->write(pop @$cmds);
        $_[KERNEL]->yield('ReadDbgr' => @_[ARG0..$#_]);
    }
}

1;

