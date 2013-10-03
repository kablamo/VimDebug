#!perl

use strict;
use warnings;
use Test::More;
use Dir::Self;
use lib __DIR__;
use TestVimDebugTalker;
use Vim::Debug::Daemon;
use File::Temp;
use File::Slurp;

# --------------------------------------------------------------------
my $T = TestVimDebugTalker->new(
    talker => Vim::Debug::Daemon->start,
);

my $pid = fork;
die "Couldn't fork.\n" unless defined $pid;

if ($pid == 0) {
        # Child process.
    Vim::Debug::Daemon->run;
}
else {
        # Parent process.
    POE::Kernel->stop;
}
END { kill 1, $pid }

# --------------------------------------------------------------------
package Tester;
use Moose;

has data  => ( is => 'rw', isa => 'Str', default => '' );

has chat  => ( is => 'rw', isa => 'CodeRef', default => sub {} );

sub test_it {
    my ($self) = @_;
    $self->chat->($self, $self->data);
}

sub mk_start {
    my ($self) = @_;
    my $tmp_file = File::Temp->new(UNLINK => 0);
    my $file_name = $tmp_file->filename();
    File::Slurp::write_file($file_name, $self->data);
    return $file_name;
}

# --------------------------------------------------------------------
my %tests;

# --------------------------------------------------------------------
$tests{null} = Tester->new(
    data => '',
    chat => sub {
        $T->send_check('start:Perl::', 'status', "bad_cmd");
    },
);

# --------------------------------------------------------------------
$tests{bad_cmd} = Tester->new(
    data => '',
    chat => sub {
        $T->send_check('start:Perk::', 'status', "bad_cmd");
        $T->send_check('stop', status => "stopped");
    },
);

# --------------------------------------------------------------------
$tests{hello} = Tester->new(
    data => << 'EOD',
print "Hello world.\n";
EOD
    chat => sub {
        my ($self) = @_;
        my $f = $self->mk_start;
        $T->send_check("start:Perl:$f:", status => "ready", line => 1);
        $T->send_check('stop',    status => "stopped");
        $T->send_check('restart', status => "ready", line => 1);
        $T->send_check('reart',  status => "bad_cmd");
        $T->send_check('restart', status => "ready", line => 1);
       # $T->send_check('stop');
       # $T->send_check('quit_daemon');
       # $T->send_check('quit');
       # $T->send_check('next');
       # $T->send_check(... 'line', 10);
       # $T->send_check('cont');
       # $T->send_check('restart');
       # $T->send_check('break foo');
        unlink $f;
    },
);

# --------------------------------------------------------------------
# Main.

package main;

sub {
    print(STDERR "    # $_\n"), $tests{$_}->test_it for keys %tests;
}->();

Test::More::done_testing;

# --------------------------------------------------------------------
__END__

Can/should the following have tests?:

        # CAN'T BE BROKEN.
    ++$x while 1;
    1;

        # CAN'T BE BROKEN, CAN IT?
    sleep 1 while 1;
    1;

        # INFINITE LOOP.
    while (1) {
        sleep 1;
    }

        # INFINITE LOOP.
    while (1) {
        ++$x;
    }

        # FAILS TO COMPILE.
    sub oogetyboogety {
    1;

        # FAILS TO COMPILE.
    sd + 4443^^ flkj

        # RUNTIME ERROR.
    oogetyboogety();

