package TestVimDebugTalker;
use Moose;

has talker => (is  => 'rw', isa => 'Vim::Debug::Talker');

sub send_check {
    my ($self, $cmd, %exp) = @_;
   # print STDERR "-> send_check $cmd\n";
    $self->send($cmd)->wait->recv;
    for my $k (keys %exp) {
        $self->chk($k, $exp{$k});
    }
   # print STDERR "<- send_check\n";
    return $self;
}

    # Send a command to the daemon.
sub send {
    my ($self, $cmd) = @_;
    $self->talker->send($cmd);
    return $self;
}

    # Blocks until a done file is produced by the talker.
sub wait {
    my ($self) = @_;
    1 while ! -f $self->talker->done_file;
    return $self;
}

    # Careful, this is blocking.
sub recv {
    my ($self) = @_;
    $self->talker->recv;
    return $self;
}

sub chk {
    my ($self, $what, $exp) = @_;
    my $got = $self->talker->dbgr_state->{$what};
    Test::More::is($got, $exp, "Check '$what' is '$exp'");
}

# --------------------------------------------------------------------
1;

