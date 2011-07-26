#!/usr/bin/perl

use strict;

use lib qw(lib t/lib);
use VimDebug::Client;
use VimDebug::Daemon;
use Test::More;
$|=1;

$SIG{INT} = \&signalHandler;
sub signalHandler { exit } # die when children die

my $testFile = 't/perl.stop.pl';
my $r;
my $firstLine;

my $pid1 = fork;
if (!$pid1) { # child process
    VimDebug::Daemon->new->run;
    exit;
}

my $pid2 = fork;
if (!$pid2) { # child process

    sleep 3;
    my $client2 = VimDebug::Client->new({
        language => 'Perl',
        dbgrCmd  => "perl -Ilib -d $testFile",
    });

warn "ok ok oko ko kok ok okok o kok ok ";
    $r = $client2->stop;
    sleep 2;
    exit;
}

my $client1 = VimDebug::Client->new({
    language => 'Perl',
    dbgrCmd  => "perl -Ilib -d $testFile",
});

$r = $client1->start;
print STDERR "0.1 YOoooooooOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO";
$firstLine = $r->line;
ok($firstLine, "connected: line number");
is($r->file, $testFile, "connected: file");

$r = $client1->cont;
ok($r->line, "continue: line number");
ok($r->file, "continue: file");

$r = $client1->restart;
is($r->line, $firstLine, "continue: line number");
is($r->file, $testFile,  "continue: file");

$r = $client1->quit;


done_testing;


