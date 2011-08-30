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

use strict;
use warnings;
use feature qw(say);
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors( qw(status line file output value) );


# constants
$Vim::Debug::Client::Response::VERSION = "0.00";


1;

