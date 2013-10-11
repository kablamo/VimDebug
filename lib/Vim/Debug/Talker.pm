# ABSTRACT: Help with communication between the daemon and the debugger.
package Vim::Debug::Talker;
# VERSION

=head1 SYNOPSIS

        # Get a Vim::Debug::Talker instance from this class.
    use Vim::Debug::Daemon;
    my $talker = Vim::Debug::Daemon->start;

        # Now we fork. The child will run the daemon, and the parent
        # will drop POE and from now on use $talker to communicate
        # with the daemon.
    my $pid = fork;
    if (! defined $pid) {
        die "Couldn't fork daemon.";
    }
    elsif ($pid == 0) {
            # Child process.
        Vim::Debug::Daemon->run;
        exit;
    }

    # Parent process.

        # No POE here.
    POE::Kernel->stop;

        # Start a debugger session. send() removes the done_file (if
        # it exists).
    $talker->send("start:Perl:foo.pl:42 qwerty");

        # Wait until the daemon has created the done_file.
    1 while ! -f $talker->done_file;

        # Get the response.
    $talker->recv;

=head1 DESCRIPTION

You obtain a Vim::Debug::Talker instance by calling Vim::Debug::Daemon->start

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

=cut
use Moose;
use IO::Socket;

=attr done_file

The presence of this file indicates that the debugger process has sent
a response that we can retrieve with recv().

=attr port

The port the daemon is listening on.

=attr dbgr_state

A hash ref with keys qw<status file line result output>, that is, the
status of the instance and the last values obtained from the debugger
process with recv().

=cut
my $vdRecSep = " -vdRecSep- ";
my $vdMsgEnd = " -vdMsgEnd-";

has done_file  => (is  => 'ro', isa => 'File::Temp', required => 1);

has port       => (is  => 'ro', isa => 'Int', required => 1);

has dbgr_state => (is => "rw", isa => "HashRef");

    # Have two sockets: a main one and one for interrupt.
for my $socket_id (qw<main intr>) {
        #~ _main_socket
    has "_${socket_id}_socket" => (
        is  => 'ro',
        isa => 'IO::Socket::INET',
        lazy => 1,
        default => sub {
            my ($self) = @_;
            return IO::Socket::INET->new(
                Proto    => "tcp",
                PeerAddr => "localhost",
                PeerPort => $self->port,
            );
        },
    );
}

sub _create_done_file {
    my ($self) = @_;
    my $df = $self->done_file;
    open my $df_h, ">", $df or die "Can't write to $df: $!\n";
    print $df_h "\n";
    close $df_h;
}

=method send($request)

First removes the done_file, then sends $request to the daemon through
the main socket. The daemon will signal that it is done with the
request by creating the done_file() again, whose presence we can later
check for.

=cut
sub send {
    my ($self, $data) = @_;
        # Removing the done_file means the debugger may be busy
        # preparing a response.
    unlink $self->done_file;
    print {$self->_main_socket} "$data\n";
    return $self;
}

=method interrupt()

Sends an interrupt request to the daemon through a secondary socket.

=cut
sub interrupt {
    my ($self) = @_;
    print {$self->_intr_socket} "interrupt\n";
    return $self;
}

=method recv()

Calling this will blockingly read from the main socket until the
vdMsgEnd mark is received, so better call it only after ascertaining
the presence of the done_file.

After stripping the vdMsgEnd, the received string will consist of the values of

joined with the vdRecSep.

This is blocking, 

, which we'll then remove

Sets the values of $self->dbgr_state to the values obtained

Return a ref to a hash representing the values of:

        status
        file
        line
        result
        output

as returned by the debugger, by keeping on 

vdRecSep. This is blocking, 

vdRecSep. This is blocking, so better call it only after ascertaining
the presence of the done_file.

=cut
sub recv {
    my ($self) = @_;
    my $data = '';
    while (1) {
        my $d = readline($self->_main_socket);
        $data .= $d;
        last if $data =~ s/\Q$vdMsgEnd\E\r\n$//;
    }
    my @f = split /\Q$vdRecSep/, $data;
    return $self->dbgr_state({
        status => $f[0],
        file   => $f[1],
        line   => $f[2],
        result => $f[3],
        output => $f[4],
    });
}

=method response($vim_debug)

Joins with vdRecSep the values qw<status file line result output> of a
Vim::Debug instance or of a hashref who has the appropriate key-value
pairs, appended with vdMsgEnd.

=cut
sub response {
    my ($pkg, $vim_debug) = @_;
    return join(
        $vdRecSep,
        map {
            defined($vim_debug->$_) ? $vim_debug->$_ : ""
        } qw<status file line result output>,
    ) . $vdMsgEnd;
}

=method custom_response($href)

Joins with vdRecSep the values of the keys qw<status file line result
output> of its hash ref argument, appended with vdMsgEnd.

=cut
sub custom_response {
    my ($pkg, $href) = @_;
    return join(
        $vdRecSep,
        map {
            defined($href->{$_}) ? $href->{$_} : ""
        } qw<status file line result output>,
    ) . $vdMsgEnd;
}

1;

