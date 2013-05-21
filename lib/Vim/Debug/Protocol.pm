# ABSTRACT: Everything needed for the VimDebug network protocol

=head1 SYNOPSIS

    package Vim::Debug::Protocol;

    # respond to a client that just connected
    my $connect = Vim::Debug::Protocol->connect($sessionId);

    # tell the client to disconnect
    my $disconnect = Vim::Debug::Protocol->disconnect;

    # respond to a client command with the current debugger state
    my $dbgr = Vim::Debug->new( language => 'Perl', invoke => 'cmd')->start;
    my $response = Vim::Debug::Protocol->respond( $dbgr->status );

=head1 DESCRIPTION

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

This module implements the network protocol between Vim and the
Vim::Debug::Daemon.  It worries about end of field and end of message strings
and all that sort of formatting.

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

After every message, the daemon also touches a file.  Which is kind of crazy
and should be fixed but is currently necessary because the vimscript is doing
nonblocking reads on the sockets.

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
package Vim::Debug::Protocol;

# VERSION

use Moose;
use MooseX::ClassAttribute;

=head1 Attributes

These values all indicate the current state of the debugger.

=head2 line()

=head2 file()

=head2 status()

=head2 value()

=head2 output()

=cut
has status     => ( is => 'rw', isa => 'Str' );
has line       => ( is => 'rw', isa => 'Int' );
has file       => ( is => 'rw', isa => 'Str' );
has value      => ( is => 'rw', isa => 'Str' );
has output     => ( is => 'rw', isa => 'Str' );

# protocol constants
# "eor": end of record; "eom": end of message.
class_has k_compilerError => ( is => 'ro', isa => 'Str', default => 'compiler error' );
class_has k_runtimeError  => ( is => 'ro', isa => 'Str', default => 'runtime error' );
class_has k_dbgrReady     => ( is => 'ro', isa => 'Str', default => 'debugger ready' );
class_has k_appExited     => ( is => 'ro', isa => 'Str', default => 'application exited' );
class_has k_eor           => ( is => 'ro', isa => 'Str', default => ' {-VDEOR-} ' );
class_has k_eom           => ( is => 'ro', isa => 'Str', default => " {-VDEOM-}" );
class_has k_badCmd        => ( is => 'ro', isa => 'Str', default => 'bad command' );
class_has k_connect       => ( is => 'ro', isa => 'Str', default => 'CONNECT' );
class_has k_disconnect    => ( is => 'ro', isa => 'Str', default => 'DISCONNECT' );
class_has k_doneFile      => ( is => 'ro', isa => 'Str', default => '.vdd.done' );

=func connect($sessionId)

Returns formatted string that is used to reply to a client who just connected
to Vim::Debug::Daemon.

=cut
sub connect {
    my $class = shift or die;
    my $sessionId = shift or die;
    return $class->response( status => k_connect(), value => $sessionId );
}

=func disconnect()

Returns formatted string that is used to tell a client to disconnect from
Vim::Debug::Daemon.

=cut
sub disconnect {
    my $class = shift or die;
    return $class->response( status => k_disconnect() );
}

=func response()

Any of the class attributes can be passed to this method.

Returns formatted string that is used to tell respond to a client that is
talking to the Vim::Debug::Daemon.

=cut
sub response {
    my $class = shift;
    my $self  = $class->new(@_);
    my $response;
    foreach my $attr (qw/status line file value output/) {
        $response .= $self->$attr if defined $self->$attr;
        $response .= $self->k_eor unless $attr eq 'output';
    }
    $response .= $self->k_eom;
    return $response;
}

=func touch()

This method needs to be called after send a message to Vim.  It creates a
file.

=cut
sub touch {
    open FILE, ">", Vim::Debug::Protocol->k_doneFile;
    print FILE "\n";
    close FILE;
}

=head1 SEE ALSO

L<Vim::Debug::Daemon>

=cut
1;
