# ABSTRACT: Vim::Debug Client

=head1 SYNOPSIS

   use Vim::Debug::Client;
   Vim::Debug::Client->connect();

=head1 DESCRIPTION

This module implements a Vim::Debug client.  The client communicates with the
Vim::Debug::Daemon.  Its probably only useful for testing.

=cut

package Vim::Debug::Client;

use strict;
use warnings;
use feature qw(say);
use base qw(Class::Accessor::Fast);

use Net::Telnet;
use Vim::Debug::Client::Response;

__PACKAGE__->mk_accessors( qw(language dbgrCmd telnet sessionId) );


# constants
$Vim::Debug::Client::VERSION = "0.00";
$| = 1;

# protocol constants
my $EOR            = '[vimdebug.eor]';       # end of record
my $EOR_REGEX      = qr/\[vimdebug.eor\]/;
my $EOR_LENGTH     = length($EOR);
my $EOM            = "\r\nvimdebug.eom\n";   # end of message
my $EOM_REGEX      = '/\nvimdebug.eom\n/';
my $BAD_CMD        = "bad command";
my $CONNECT        = "CONNECT";
my $DISCONNECT     = "DISCONNECT";

# connection constants
my $DONE_FILE = ".vdd.done";


sub connect {
    my $self = shift or die;

    my $telnet = Net::Telnet->new(
        Timeout    => 10,
        Prompt     => $EOM_REGEX,
        Rs         => $EOR, # input  record separator -- not a regex
        Ors        => "\n", # output record separator -- not a regex
        Telnetmode => 0,
        Port       => 6543,
    );
    $self->telnet($telnet);

    # retry connect 5 times; sleep 1 second between attempts
    my $connectAttempts = 0;
    while (1) {
        eval { $self->telnet->open };
        $connectAttempts++;
        die $@ if ($@ && $connectAttempts > 5);
        (sleep 1 && next) if $@;
        last;
    }

    my ($output, $eom) = $telnet->waitfor($EOM_REGEX);
    my @parts = split($EOR_REGEX, $output);

    $self->sessionId($parts[-1]);

    return;
}

sub start {
    my $self = shift or die;

    $self->connect;

    my $cmd = sprintf( 
        'start:%s:%s:%s', 
        $self->sessionId, 
        $self->language,
        $self->dbgrCmd,
    );
    my @response= $self->telnet->cmd($cmd);

    return $self->buildResponse(@response);
}

sub stop {
    my $self = shift or die;
    $self->connect;
    $self->telnet->cmd("stop:" . ($self->sessionId - 1));
    return;
}

sub jfdi {
    my ($self, $cmd) = @_;
    my @response = $self->telnet->cmd( $cmd );
    return $self->buildResponse(@response);
}

sub buildResponse {
    my ( $self, @response) = @_;

    @response = map { substr($_, 0, -$EOR_LENGTH) } @response;

    my $response = Vim::Debug::Client::Response->new({
        status => $response[0],
        line   => $response[1],
        file   => $response[2],
        value  => $response[3],
        output => $response[4],
    });

    return $response;
}

sub next     { my ($self)         = @_; return $self->jfdi("next")        }
sub step     { my ($self)         = @_; return $self->jfdi("step")        }
sub cont     { my ($self)         = @_; return $self->jfdi("cont")        }
sub break    { my ($self, $l, $f) = @_; return $self->jfdi("break:$l:$f") }
sub clear    { my ($self, $l, $f) = @_; return $self->jfdi("clear:$l:$f") }
sub clearAll { my ($self)         = @_; return $self->jfdi("clearAll")    }
sub print    { my ($self, $s)     = @_; return $self->jfdi("print:$s")    }
sub command  { my ($self, $s)     = @_; return $self->jfdi("command:$s")  }
sub restart  { my ($self)         = @_; return $self->jfdi("restart")     }
sub quit     { 
    my ($self) = @_; 
    $self->telnet->cmd("quit");
    return 1;
}



1;
