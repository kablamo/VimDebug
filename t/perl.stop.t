#!/usr/bin/perl

use strict;

use lib qw(lib t/lib);
use Vim::Debug::Client;
use Vim::Debug::Daemon;
use Test::More;
$|=1;

$SIG{INT} = \&signalHandler;
sub signalHandler { exit } # die when children die

my $testFile = 't/perl.stop.pl';
my $r;
my $firstLine;

my $pid1 = fork;
if (!$pid1) { # child process
    Vim::Debug::Daemon->new->run;
    exit;
}

my $pid2 = fork;
if (!$pid2) { # child process

    sleep 3;
    my $client2 = Vim::Debug::Client->new({
        language => 'Perl',
        dbgrCmd  => "perl -Ilib -d $testFile",
    });

    $r = $client2->stop;
    exit;
}

my $client1 = Vim::Debug::Client->new({
    language => 'Perl',
    dbgrCmd  => "perl -Ilib -d $testFile",
});

$r = $client1->start;
$firstLine = $r->line;
ok($firstLine, "connected: line number");
is($r->file, $testFile, "connected: file");

$r = $client1->cont;
ok($r->line, "continue: line number");
ok($r->file, "continue: file");

$r = $client1->next;
is($r->file, $testFile, "next: file");

$r = $client1->restart;
is($r->line, $firstLine, "continue: line number");
is($r->file, $testFile,  "continue: file");

$r = $client1->quit;


done_testing;


