# ABSTRACT: VimDebug Client Response
=head1 SYNOPSIS

    use VimDebug::Client::Response;
    VimDebug::Client::Response->new(
        status => 'debuggerReady',
        line   => 1,
        file   => 't/perl.pl',
        output => 'some output',
    );

=head1 DESCRIPTION

This module implements a VimDebug client response.  The client communicates with the
VimDebug::Daemon.  This response is parsed and this object is created.

=cut

package VimDebug::Client::Response;

use strict;
use warnings;
use feature qw(say);
use base qw(Class::Accessor::Fast);

use Data::Dumper::Concise;

__PACKAGE__->mk_accessors( qw(status line file output) );


# constants
$VimDebug::Client::Response::VERSION = "0.00";


1;

