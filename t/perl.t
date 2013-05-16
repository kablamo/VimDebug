#!perl

use strict;
use warnings;

use lib qw(lib t/lib);
use Vim::Debug::Client;
use Vim::Debug::Daemon;
use Test::More;

    # Die when children die.
$SIG{INT} = sub { exit };

my $pid = fork;
if (!$pid) {
    # child process
    Vim::Debug::Daemon->new->run;
    exit;
}

# parent
my $r; # response
my $firstLine;
my $lastLine;
my $testFile = 't/perl.pl';
my $client = Vim::Debug::Client->new({
    language => 'Perl',
    dbgrCmd  => "perl -Ilib -d $testFile",
});

{
    note("core debugger functions");

    $r = $client->start;
    $firstLine = $r->line;
    ok($firstLine, "connected: line number");
    is($r->file, $testFile, "connected: file");

    $r = $client->next;
    is($r->line, $firstLine + 1, "next: line number");
    is($r->file, $testFile, "next: file");

    $r = $client->step;
    is($r->line, $firstLine + 2, "step: line number");
    is($r->file, $testFile, "step: file");

    $r = $client->print('$a');
    is($r->line, $firstLine + 2, "print: line number");
    is($r->file, $testFile, "print: line number");
    is($r->value, '0  1', "print: value");

    continueToTheEnd();
    restart();
}

{
    note("breakpoint tests");

    ok $client->break(7, $testFile), "set breakpoint 0";

    $r = $client->cont;
    is($r->line, 7, "continue to breakpoint: line number");
    is($r->file, $testFile, "continue to breakpoint: file");

    continueToTheEnd();
    restart();

    ok $client->clear(7, $testFile), "clear breakpoint";

    continueToTheEnd();
    restart();

    ok $client->break(7, $testFile), "set breakpoint 1";

    ok $client->break(8, $testFile), "set breakpoint 1";

    ok $client->clearAll, "clear breakpoint";

    continueToTheEnd();
    restart();
}

$r = $client->command("n");
is($r->line, $firstLine + 1, "command:n: line number");
is($r->file, $testFile, "command:n: file");
is($r->value, '', 'command:n: value');

$r = $client->command('x $a');
is($r->line, $firstLine + 1, 'command:x $a: line number');
is($r->file, $testFile, 'command:x $a: file');
is($r->value, '0  1', 'command:x $a: value');

ok $client->quit, "quit";

done_testing;

sub continueToTheEnd {
    $r = $client->cont;
    ok($r->line, "continue: line number");
    ok($r->file, "continue: file");
}

sub restart {
    $r = $client->restart;
    is($r->line, $firstLine, "restart: line number");
    is($r->file, $testFile, "restart: file");
}
