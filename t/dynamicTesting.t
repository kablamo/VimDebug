#!/usr/bin/perl

use strict;

use File::Which;
use VimDebug::DebuggerInterface::Test;
use Test::More;

my @testList = ();
foreach my $dbgr (qw(Perl Python Ruby)) {

   # load module
   my $moduleName = 'VimDebug/DebuggerInterface/' . $dbgr . '.pm';
   require $moduleName ;

   my $path = eval '$VimDebug::DebuggerInterface::' . $dbgr . '::dbgrPath;';
   if (not defined File::Which::which($path)) {
      next;
   }

   my $test = VimDebug::DebuggerInterface::Test->new(
      debuggerName => $dbgr,
      testCode     => "t/${dbgr}.testCode",
   );
   push @testList, $test;
}

Test::Class->runtests(@testList);

