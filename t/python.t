#!/usr/bin/perl

use strict;

use File::Which;
use lib 'lib';
use VimDebug::DebuggerInterface::Test;
use VimDebug::DebuggerInterface::Python;
use Test::More;


if (not defined File::Which::which('python')) {
   return;
}

my $test = VimDebug::DebuggerInterface::Test->new(
   debuggerName    => 'Python',
   debuggerCommand => [qw(pdb t/python.t)],
   filename        => 't/python.t',
);

Test::Class->runtests($test);

