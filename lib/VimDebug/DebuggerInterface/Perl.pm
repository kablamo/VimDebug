# (c) eric johnson 2002-3020
# email: vimDebug at iijo dot org
# http://iijo.org
# ABSTRACT: VimDebug Perl interface.


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
   my $self        = shift or confess;
   my @incantation = @_;

   $ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
   #$ENV{"PERLDB_OPTS"} = "ReadLine=0,ornaments=''";
   $ENV{"PERLDB_OPTS"} = "ornaments=''";

   $self->dbgrPromptRegex($dbgrPromptRegex); # used to parse debugger output
   return $self->SUPER::_startDebugger(\@incantation);
}

sub next {
   my $self = shift or confess;
   $self->SUPER::_command("n");
   return undef;
}

sub step {
   my $self = shift or confess;
   $self->SUPER::_command("s");
   return undef;
}

sub cont {
   my $self = shift or confess;
   $self->SUPER::_command("c");
   return undef;
}

sub setBreakPoint {
   my $self       = shift or confess;
   my $lineNumber = shift or confess;
   my $fileName   = shift or confess;

   $self->SUPER::_command("f $fileName");
   $self->SUPER::_command("b $lineNumber");

   return $lineNumber;
}

sub clearBreakPoint {
   my $self       = shift or confess;
   my $lineNumber = shift or confess;
   my $fileName   = shift or confess;

   $self->SUPER::_command("f $fileName");
   $self->SUPER::_command("B $lineNumber");

   return undef;
}

sub clearAllBreakPoints {
   my $self = shift or confess;
   return $self->SUPER::_command("B *");
   return undef;
}

sub printExpression {
   my $self       = shift or confess;
   my $expression = shift or confess;
   return $self->SUPER::_command("x $expression");
}

sub command {
   my $self = shift or confess;
   my $command = shift or confess;
   return $self->SUPER::_command($command);
}
 
sub restart {
   my $self = shift or confess;
   $self->SUPER::_command("R");
   return undef;
}

sub quit {
   my $self = shift or confess;
   return $self->SUPER::_quit("q");
}

sub parseOutput {
   my $self   = shift or confess;
   my $output = shift or confess;

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
   my $self   = shift or confess;
   my $output = shift or confess;
   my ($filePath, undef) = _getFileAndLine($output);
   $self->filePath($filePath) if defined $filePath;
   return undef;
}

sub parseForLineNumber {
   my $self   = shift or confess;
   my $output = shift or confess;
   my (undef, $lineNumber) = _getFileAndLine($output);
   $self->lineNumber($lineNumber) if defined $lineNumber;
   return undef;
}

sub _getFileAndLine {
   # See .../t/VD_DI_Perl.t for test cases.
   my ($str) = shift;
   return $str =~ /
      ^ \w+ ::
      (?: \w+ :: )*
      (?: CODE \( 0x \w+ \) | \w+ )?
      \(
         (?: .* \x20 )?
         ( .+ ) : ( \d+ )
      \):
   /xm ? ($1, $2) : (undef, undef);
}


1;
