package VimDebug::DebuggerInterface::CompilerErrorTest;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use VimDebug::DebuggerInterface;
use Test::More;
use File::Spec;
use base qw(Test::Class);


sub createDebugger : Test(startup) {
   my $self = shift or die;

   confess "debuggerName not defined" unless exists $self->{debuggerName};
   confess "testCode not defined" unless exists $self->{testCode};

   # load module
   my $moduleName = 'VimDebug/DebuggerInterface/' . $self->{debuggerName} . '.pm';
   require $moduleName ;

   # create debugger object
   my $className = 'VimDebug::DebuggerInterface::' . $self->{debuggerName};
   $self->{dbgr} = eval $className . "->new();";
   if (not defined $self->{dbgr}) {
      die  "no such module exists: $className";
   }

   # make sure test code exists
   if (! -r $self->{testCode}) {
      die "file not readable: " . $self->{testCode};
   }
}


sub startDebugger : Test(2) {
   my $self = shift or confess;
   my $dbgr = $self->{dbgr};
   $dbgr->startDebugger($self->{testCode});
   ok(!defined $dbgr->lineNumber)  or diag("line number defined");
   ok(!defined $dbgr->filePath)    or diag("file path defined");
   $dbgr->quit();
}

#sub restart : Test(1) {
#   my $self = shift or confess;
#   my $dbgr = $self->{dbgr};
#   $dbgr->restart($self->{testCode});
#   ok($dbgr->compilerError) or diag("should have had a compiler error");
#   $dbgr->quit();
#}

1;

