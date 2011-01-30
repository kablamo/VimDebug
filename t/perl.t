#!/usr/bin/perl

use strict;

use File::Which;
use lib 'lib';
use VimDebug::DebuggerInterface::Test;
use VimDebug::DebuggerInterface::Perl;
use Test::More;


if (not defined File::Which::which('perl')) {
   return;
}

my $test = VimDebug::DebuggerInterface::Test->new(
   debuggerName    => 'Perl',
   debuggerCommand => [qw(perl -Ilib -d t/Perl.testCode)],
   filename        => 't/Perl.testCode',
);

Test::Class->runtests($test);

