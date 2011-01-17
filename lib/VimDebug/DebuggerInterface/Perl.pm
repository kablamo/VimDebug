# Perl.pm
#
# perl debugger interface for vimDebug
#
# (c) eric johnson 2002-3020
# distribution under the GPL
#
# email: vimDebug at iijo dot org
# http://iijo.org
#
# $Id: Perl.pm 93 2007-12-22 21:05:20Z eric $


package VimDebug::DebuggerInterface::Perl;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use base qw(VimDebug::DebuggerInterface::Base);


# set some global variables

our $dbgrPath           = "perl";
my  $dbgrPromptRegex    = '  DB<+\d+>+ ';
my  $compilerErrorRegex = 'aborted due to compilation error';
my  $runtimeErrorRegex  = ' at .* line \d+';
my  $finishedRegex      = qr/(\/perl5db.pl:)|(Use .* to quit or .* to restart)|(\' to quit or \`R\' to restart)/;


# callback functions implemented

sub startDebugger {
   my $self               = shift or die;
   my $path               = shift or die;
   my @commandLineOptions = @_;

   $ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
   #$ENV{"PERLDB_OPTS"} = "ReadLine=0,ornaments=''";
   $ENV{"PERLDB_OPTS"} = "ornaments=''";

   my   @incantation = $dbgrPath;
   push(@incantation, "-d");
   push(@incantation, $path);
   push(@incantation, @commandLineOptions);

   # this regexe aids in parsing debugger output.
   $self->dbgrPromptRegex($dbgrPromptRegex);
   return $self->SUPER::_startDebugger(\@incantation);
}

sub next {
   my $self = shift or die;
   $self->SUPER::_command("n");
   return undef;
}

sub step {
   my $self = shift or die;
   $self->SUPER::_command("s");
   return undef;
}

sub cont {
   my $self = shift or die;
   $self->SUPER::_command("c");
   return undef;
}

sub setBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   $self->SUPER::_command("f $fileName");
   $self->SUPER::_command("b $lineNumber");

   return $lineNumber;
}

sub clearBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   $self->SUPER::_command("f $fileName");
   $self->SUPER::_command("B $lineNumber");

   return undef;
}

sub clearAllBreakPoints {
   my $self = shift or die;
   return $self->SUPER::_command("B *");
   return undef;
}

sub printExpression {
   my $self       = shift or die;
   my $expression = shift or die;
   return $self->SUPER::_command("x $expression");
}

sub command {
   my $self = shift or die;
   my $command = shift or die;
   return $self->SUPER::_command($command);
}
 
sub restart {
   my $self = shift or die;
   $self->SUPER::_command("R");
   return undef;
}

sub quit {
   my $self = shift or die;
   return $self->SUPER::_quit("q");
}

sub parseOutput {
   my $self   = shift or die;
   my $output = shift or die;

   # take care of the problem case when we hit an eval() statement
   # example: main::function((eval 3)[debugTestCase.pl:5]:1):      my $foo = 1
   # this will turn that example debugger output into:
   #          main::function(debugTestCase.pl:5):      my $foo = 1
   if ($output =~  /\w*::(\w*)\(+eval\s+\d+\)+\[(.*):(\d+)\]:\d+\):/om) {
       $output =~ s/\w*::(\w*)\(+eval\s+\d+\)+\[(.*):(\d+)\]:\d+\):/::$1($2:$3):/m;
   }

   return $self->SUPER::parseOutput($output);
}

sub parseForFilePath {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /\w*::(\w*)?\(+(.+):(\d+)\)+:/om) {
      $self->filePath($2);
   }
   return undef;
}

sub parseForLineNumber {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /\w*::(\w*)?\(+(.+):(\d+)\)+:/om) {
      $self->lineNumber($3);
   }
   return undef;
}

sub output {
   my $self = shift or die;
   my $output;

   if (@_) {
      $output = shift;
      $output =~ s/\n/\n/mg;
      $output =~ s//\n/mg;
      $output =~ s///mg;
      return $self->SUPER::output($output);
   }
   else {
      return $self->SUPER::output();
   }
}


1;
