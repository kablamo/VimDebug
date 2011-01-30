# (c) eric johnson 2002-3020
# email: vimDebug at iijo dot org
# http://iijo.org


package VimDebug::DebuggerInterface::Python;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use base qw(VimDebug::DebuggerInterface::Base);


# set some global variables

our $dbgrPath           = "pdb";
my  $dbgrPromptRegex    = '\(Pdb\) $';


# callback functions implemented

sub startDebugger {
   my $self        = shift or die;
   my @incantation = @_;

   $self->{breakPointList}  = {};
   $self->{breakPointCount} = 1;
   $self->{incantation}     = \@incantation;

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

   $fileName = File::Spec->rel2abs($fileName);

   if (exists $self->{breakPointList}->{"$fileName:$lineNumber"}) {
      $self->clearBreakPoint($lineNumber, $fileName);
   }

   $self->SUPER::_command("b $fileName:$lineNumber");

   $self->{breakPointList}->{"$fileName:$lineNumber"} = $self->{breakPointCount};
   $self->{breakPointCount}++;

   return $lineNumber;
}

sub clearBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   $fileName = File::Spec->rel2abs($fileName);
   my $breakPointCount = $self->{breakPointList}->{"$fileName:$lineNumber"};
   $self->SUPER::_command("clear $breakPointCount");
   delete $self->{breakPointList}->{"$fileName:$lineNumber"};

   return undef;
}

sub clearAllBreakPoints {
   my $self = shift or die;

   foreach my $breakPoint (keys(%{$self->{breakPointList}})) {
      my ($fileName, $lineNumber) = split(/:/, $breakPoint);
      $self->clearBreakPoint($lineNumber, $fileName);
   }

   return undef;
}

sub printExpression {
   my $self       = shift or die;
   my $expression = shift or die;
   return $self->SUPER::_command("p $expression");
}

sub command {
   my $self = shift or die;
   my $command = shift or die;
   return $self->SUPER::_command($command);
}
 
sub restart {
   my $self = shift or die;

   # restart
   my $oldBreakPointList = $self->{breakPointList};
   $self->SUPER::_command("quit");
   $self->startDebugger(@{$self->{incantation}});

   # restore break points
   foreach my $breakPoint (keys(%$oldBreakPointList)) {
      $self->{breakPointList}->{$breakPoint} = $self->{breakPointCount};
      $self->{breakPointCount}++;
      $self->SUPER::_command("b $breakPoint");
   }
   return undef;
}

sub quit {
   my $self = shift or die;
   return $self->SUPER::_quit("q");
}

sub parseForFilePath {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /^> (.+)\((\d+)\).+/om) {
      $self->filePath($1);
   }
   return undef;
}

sub parseForLineNumber {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /^> (.+)\((\d+)\).+/om) {
      $self->lineNumber($2);
   }
   return undef;
}


1;
