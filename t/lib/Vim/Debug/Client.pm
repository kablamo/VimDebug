# ABSTRACT: A Vim::Debug client, for testing.

=head1 SYNOPSIS

    use Vim::Debug::Client;
    Vim::Debug::Client->connect();

=head1 DESCRIPTION

This module implements a Vim::Debug client. The client communicates
with the Vim::Debug::Daemon.  It's probably only useful for testing.

=cut
package Vim::Debug::Client;
use Moose;
use warnings;

# VERSION

use Net::Telnet;
use Vim::Debug::Protocol;

# constants
$Vim::Debug::Client::VERSION = "0.1";
$| = 1;

# protocol constants
my $EOM       = Vim::Debug::Protocol->k_eom . "\n";
my $EOM_REGEX = "/\Q$EOM\E/";

# connection constants
has language  => ( is => 'ro', isa => 'Str' );
has dbgrCmd   => ( is => 'ro', isa => 'Str' );
has telnet    => ( is => 'rw', isa => 'Net::Telnet' );
has sessionId => ( is => 'rw', isa => 'Int' );

has _protocol => ( 
    is          => 'ro', 
    isa         => 'Vim::Debug::Protocol', 
    default     => sub { Vim::Debug::Protocol->new },
    handles     => [qw/k_eor k_eom k_connect k_disconnect/],
);

sub connect {
    my $self = shift or die;

    my $telnet = Net::Telnet->new(
        Timeout    => 10,
        Prompt     => $EOM_REGEX,
        Rs         => $self->k_eor, # input  record separator -- not a regex
        Ors        => "\n", # output record separator -- not a regex
        Telnetmode => 0,
        Port       => Vim::Debug::Daemon->port,
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
    my @parts = split $self->k_eor, $output;

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

    @response = map { substr($_, 0, -length($self->k_eor)) } @response;

    my $response = Vim::Debug::Protocol->new({
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
