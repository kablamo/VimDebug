#!perl

use strict;
use warnings;
use Test::More;
use Dir::Self;
use lib __DIR__;
use File::Temp;
use File::Slurp;

use_ok('Vim::Debug');

    # We use a global $VD, beware.
my $VD;

sub chk {
    my ($what, $exp) = @_;
    return Test::More::is(
        $VD->$what,
        $exp,
        "Check $what",
    );
}

    # Test bad files.
{
    $VD = Vim::Debug->new(language => 'Perl');
    chk('status', "stopped");

    my $filename = "no_such_file";
    my $error_msg = $VD->start($filename);
    ok($VD->start($filename) ne '', "Non existent file shouldn't start."),
    chk('line', 0);
    chk('filename', $filename);
    chk('status', "filename_not_found");

}

    # Test translations.
{
    $VD = Vim::Debug->new(language => 'Perl');

        # Translated command.
    my $tc;

    $tc = $VD->translate('next');
    is_deeply($tc, [ 'n' ], "Check translation of 'next'.");

    $tc = $VD->translate('break:42:somefile');
    is_deeply($tc, [ "f somefile", "b 42" ], "Check translation of 'break...'.");
}

    # Test qw<start read write next stop>, eventually qw<stepin
    # stepout> and others.
{
    my $pl_prog_file = File::Temp->new(UNLINK => 0);
    my $pl_fname = $pl_prog_file->filename;
    File::Slurp::write_file($pl_fname, << 'EOC');
$x = $ARGV[0];
$x += 55;
1;
EOC

    $VD = Vim::Debug->new(language => 'Perl');

    is(
        $VD->start($pl_fname, '42 qwerty'),
        '',
        "'start' returns empty string when successful.",
    );
    sleep 1 until $VD->read;

    chk('filename', $pl_fname);
    chk('line', 1);
    chk('file', $pl_fname);
    chk('status', "ready");

    for my $cmd (@{$VD->translate('next')}) {
        $VD->write($cmd);
        sleep 1 until $VD->read;
    }
    chk('line', 2);
    chk('status', "ready");

    $VD->stop;
    chk('status', "stopped");

        # Start again.
    is(
        $VD->start($pl_fname, '55 bluh'),
        '',
        "'start' returns empty string when successful.",
    );
    sleep 1 until $VD->read;

    chk('line', 1);
    chk('filename', $pl_fname);
    chk('status', "ready");

    $VD->stop;
    unlink $pl_fname;
}

done_testing;

