# ABSTRACT: Everything needed for the VimDebug network protocol

=head1 SYNOPSIS

If you are new to the Vim::Debug project please read the L<Vim::Debug::Manual> first.

    package Vim::Debug::Protocol;

    my $p = Vim::Debug::Protocol->new;
   

=head1 DESCRIPTION

The Vim::Debug project integrates the Perl debugger with Vim, allowing
developers to visually step through their code and examine variables.  

If you are new to the Vim::Debug project please read the L<Vim::Debug::Manual> first.

Please note that this code is in beta and these libraries will be changing
radically in the near future.


=head1 FUNCTIONS

=cut

package Vim::Debug::Protocol;

use Moose;
use MooseX::ClassAttribute;

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

sub connect {
    my $class = shift or die;
    my $sessionId = shift or die;
    return $class->response( status => _connect(), value => $sessionId );
}

sub disconnect {
    my $class = shift or die;
    return $class->response( status => _disconnect() );
}

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

This method needs to be called after send a message to Vim.  It just creates a
file.

=cut

sub touch {
    my $DONE_FILE = ".vdd.done";
    open(FILE, ">", $DONE_FILE);
    print FILE "\n";
    close(FILE);
}


=head2 line($number)

If $number parameter is used, the line class attribute is set using that
value.  If no parameters are passed, the current value of the line
attribute is returned.

=head2 file($path)

If $path parameter is used, the file class attribute is set using that
value.  If no parameters are passed, the current value of the file
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
