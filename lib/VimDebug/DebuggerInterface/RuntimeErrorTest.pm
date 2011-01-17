package VimDebug::DebuggerInterface::RuntimeErrorTest;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use VimDebug::DebuggerInterface;
use Test::More;
use File::Spec;
use base qw(Test::Class);


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

sub step : Test(1) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->step();
   ok($dbgr->runtimeError) or diag("no runtime error");
}

sub next : Test(1) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->next();
   ok($dbgr->runtimeError) or diag("no runtime error");
}

sub cont : Test(1) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->cont();
   ok($dbgr->runtimeError) or diag("no runtime error");
}


1;
