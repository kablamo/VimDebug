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

class_has compilerError => ( is => 'ro', isa => 'Str', default => 'compiler error' );
class_has runtimeError  => ( is => 'ro', isa => 'Str', default => 'runtime error' );
class_has dbgrReady     => ( is => 'ro', isa => 'Str', default => 'debugger ready' );
class_has appExited => ( is => 'ro', isa => 'Str', default => 'application exited' );

has status     => ( is => 'rw', isa => 'Str' );
has line       => ( is => 'rw', isa => 'Int' );
has file       => ( is => 'rw', isa => 'Str' );
has value      => ( is => 'rw', isa => 'Str' );
has output     => ( is => 'rw', isa => 'Str' );

# protocol constants
# $self->eor is end of record.  $self->eom is end of message
class_has _eor        => ( is => 'ro', isa => 'Str', default => '-vimdebug.eor-' );
class_has _eom        => ( is => 'ro', isa => 'Str', default => "\r\nvimdebug.eom" );
class_has _badCmd     => ( is => 'ro', isa => 'Str', default => 'bad command' );
class_has _connect    => ( is => 'ro', isa => 'Str', default => 'CONNECT' );
class_has _disconnect => ( is => 'ro', isa => 'Str', default => 'DISCONNECT' );

=head1 FUNCTIONS

=cut

=head2 connect($sessionId)

Returns formatted string that is used to reply to a client who just connected
to Vim::Debug::Daemon.

=cut

sub connect {
    my $class = shift or die;
    my $sessionId = shift or die;
    return $class->response( status => _connect(), value => $sessionId );
}

=head2 disconnect()

Returns formatted string that is used to tell a client to disconnect from
Vim::Debug::Daemon.

=cut

sub disconnect {
    my $class = shift or die;
    return $class->response( status => _disconnect() );
}

=head2 response()

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
        $response .= $self->_eor unless $attr eq 'output';
    }
    $response .= $self->_eom;
    return $response;
}

=head2 touch()

This method needs to be called after send a message to Vim.  It creates a
file.

=cut

sub touch {
    my $DONE_FILE = ".vdd.done";
    open(FILE, ">", $DONE_FILE);
    print FILE "\n";
    close(FILE);
}


=head1 SEE ALSO

L<Vim::Debug::Daemon>


=head1 AUTHOR

Eric Johnson, cpan at iijo :dot: org

=head1 COPYRIGHT

Copyright (C) 2003 - 3090, Eric Johnson

This module has the same license as Perl.

=cut

1;
