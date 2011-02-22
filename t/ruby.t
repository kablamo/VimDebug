#!/usr/bin/perl

use strict;

use File::Which;
use lib 'lib';
use VimDebug::DebuggerInterface::Test;
use VimDebug::DebuggerInterface::Ruby;
use Test::More;


if (not defined File::Which::which('ruby')) {
   return;
}

my $test = VimDebug::DebuggerInterface::Test->new(
   debuggerName    => 'Ruby',
   debuggerCommand => [qw(ruby -rdebug t/ruby.t)],
   filename        => 't/ruby.t',
);

Test::Class->runtests($test);

