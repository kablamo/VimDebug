# ABSTRACT: Vim::Debug Client Response

=head1 SYNOPSIS

    use Vim::Debug::Client::Response;
    Vim::Debug::Client::Response->new(
        status => 'debuggerReady',
        line   => 1,
        file   => 't/perl.pl',
        value  => 'some value',
        output => 'some output',
    );

=head1 DESCRIPTION

This module implements a Vim::Debug client response.  The client communicates with the
Vim::Debug::Daemon.  This response is parsed and this object is created.

=cut

package Vim::Debug::Client::Response;

use Moose;

has status => ( is => 'rw', isa => 'Str' );
has line   => ( is => 'rw', isa => 'Int' );
has file   => ( is => 'rw', isa => 'Str' );
has output => ( is => 'rw', isa => 'Str' );
has value  => ( is => 'rw', isa => 'Str' );

# constants
$Vim::Debug::Client::Response::VERSION = "0.1";


1;

