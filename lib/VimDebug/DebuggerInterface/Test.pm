# (c) eric johnson 2002-3020
# distribution under the GPL
#
# email: vimDebug at iijo dot org
# http://iijo.org
#
# $Id: TestPerlDebugger.pm 67 2005-10-04 22:35:52Z eric $
#
#
# ALL DEBUGGER PACKAGES SHOULD PASS ALL TESTS
#
# read the perldoc at the end of this file to see how to do this.
#
# your test code which will be debugged by this script should go in the t/
# directory with all the other tests.  for example, t/perlTest contains perl
# test code to be debugged.  your test code must comply with the following
# rules in order to pass the tests:
#
# line  1:
# line  2:
# line  3:
# line  4:
# line  5: function A
# line  6: function A
# line  7: function A
# line  8: function A
# line  9:
# line 14: statement
# line 15: statement
# line 16: statement
# line 17: statement
# line  9:
# line 10: function call to function A
# line 11:
# line 12: statement
# line 12: statement
# line 12: statement
# line 12: statement
# line 18:


package VimDebug::DebuggerInterface::Test;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use VimDebug::DebuggerInterface;
use Test::More;
use File::Spec;
use base qw(Test::Class);

# globals
my $LINE_INFO      = "vimDebug:";
my $COMPILER_ERROR = "compiler error";
my $RUNTIME_ERROR  = "runtime error";
my $APP_EXITED     = "application exited";
my $DBGR_READY     = "debugger ready";

sub createDebugger : Test(startup) {
   my $self = shift or confess;

   confess "debuggerName not defined" unless exists $self->{debuggerName};
   confess "testCode not defined"     unless exists $self->{testCode};

   # load module
   my $moduleName = 'VimDebug/DebuggerInterface/' . $self->{debuggerName} . '.pm';
   require $moduleName ;

   # create debugger object
   my $className = 'VimDebug::DebuggerInterface::' . $self->{debuggerName};
   $self->{dbgr} = eval $className . "->new();";
   confess "no such module exists: $className" unless defined $self->{dbgr};

   # make sure test code exists
   if (! -r $self->{testCode}) {
      die "file not readable: " . $self->{testCode};
   }
}

sub startDebugger : Test(setup) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->startDebugger($self->{testCode});
}

sub quitDebugger : Test(teardown) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->quit();
}

sub step : Test(3) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv;
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->step(); # some dbgrs skip over the function call
   $rv = $dbgr->step(); # some dbgrs stop on the function call
   ok(defined $dbgr->lineNumber) or diag("line number not defined");
   ok(defined $dbgr->filePath)   or diag("file path not defined");
   ok($dbgr->lineNumber == 5 or
      $dbgr->lineNumber == 6   ) or diag($dbgr->lineNumber);
}

sub next : Test(3) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv;
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->step();
   $rv = $dbgr->next(); # some dbgrs skip over the function call
   $rv = $dbgr->next(); # some dbgrs stop on the function call
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
   ok($dbgr->lineNumber == 18 or
      $dbgr->lineNumber == 19   ) or diag($dbgr->lineNumber);
}

sub cont : Test(2) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv   = $dbgr->cont();
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
}

sub restart : Test(5) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv;
   $self->cont();
   $rv = $dbgr->restart(); # some dbgrs restart on the first line of code
   $rv = $dbgr->next();    # some dbgrs restart and pause before the first line
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
   ok($dbgr->lineNumber == 11 or
      $dbgr->lineNumber == 12   ) or diag($dbgr->lineNumber);
}

sub breakPoints : Test(31) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv;

   $rv = $dbgr->setBreakPoint(13, $self->{testCode});
   $dbgr->cont();
   ok(defined $rv)                or diag("setbp returned undef");
   ok($rv == 13)                  or diag("setbp returned " . $rv);
   ok(defined $dbgr->lineNumber)  or diag("before: line number not defined");
   ok(defined $dbgr->filePath)    or diag("before: file path not defined");
   ok($dbgr->lineNumber == 13)    or diag("before: " . $dbgr->lineNumber);

   $self->restart();
   $dbgr->cont();
   ok(defined $dbgr->lineNumber)  or diag("after0: line number not defined");
   ok(defined $dbgr->filePath)    or diag("after0: file path not defined");
   ok($dbgr->lineNumber == 13)    or diag("after0: " . $dbgr->lineNumber);

   $dbgr->clearBreakPoint(13, $self->{testCode});
   $self->restart();
   $dbgr->cont();
   ok(defined $dbgr->lineNumber)  or diag("after0: line number not defined");
   ok(defined $dbgr->filePath)    or diag("after0: file path not defined");
}

sub clearAllBreakPoints : Test(2) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv;
   $rv = $dbgr->setBreakPoint(13, $self->{testCode});
   $rv = $dbgr->setBreakPoint(14, $self->{testCode});
   $rv = $dbgr->clearAllBreakPoints();
   $rv = $dbgr->cont();
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
}

sub printExpression : Test(5) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   my $rv = $dbgr->printExpression('1+1');
   ok(defined $rv)                    or diag("return value not defined");
   ok($rv =~ /2/)                     or diag($rv);
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
}

sub command : Test(3) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->command("beepinfoodoo123444e");
   ok(defined $dbgr->lineNumber)  or diag("line number not defined");
   ok(defined $dbgr->filePath)    or diag("file path not defined");
}


1;
