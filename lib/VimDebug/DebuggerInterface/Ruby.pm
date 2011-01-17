# Ruby.pm
#
# perl debugger interface for vimDebug
#
# (c) eric johnson 2002-3020
# distribution under the GPL
#
# email: vimDebug at iijo dot org
# http://iijo.org
#
# $Id: Ruby.pm 93 2007-12-22 21:05:20Z eric $


package VimDebug::DebuggerInterface::Ruby;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use base qw(VimDebug::DebuggerInterface::Base);


# set some global variables

our $dbgrPath           = "ruby";
my  $dbgrPromptRegex    = '(\(rdb:\d+\) )|(Really quit\? \(y\/n\) )$';


# callback functions implemented

sub startDebugger {
   my $self               = shift or die;
   my $path               = shift or die;
   my @commandLineOptions = @_;

   $self->{breakPointList}     = {};
   $self->{breakPointCount}    = 1;
   $self->{path}               = $path;
   $self->{commandLineOptions} = \@commandLineOptions;

   my   @incantation = $dbgrPath;
   push(@incantation, "-rdebug");
   push(@incantation, $path);
   push(@incantation, @commandLineOptions);

   # this is used to parse debugger output.
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

   if (exists $self->{breakPointList}->{"$fileName:$lineNumber"}) {
      $self->clearBreakPoint($lineNumber, $fileName);
   }

   my $rv = $self->SUPER::_command("b $fileName:$lineNumber");

   $self->{breakPointList}->{"$fileName:$lineNumber"} = $self->{breakPointCount};
   $self->{breakPointCount}++;

   return $lineNumber;
}

sub clearBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   my $breakPointCount = $self->{breakPointList}->{"$fileName:$lineNumber"};
   $self->SUPER::_command("del $breakPointCount");
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

   my $oldBreakPointList = $self->{breakPointList};

   $self->startDebugger($self->{path}, @{$self->{commandLineOptions}});

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
   $self->SUPER::_command("q");
   $self->SUPER::_command("y");
   $self->dbgr->finish();
   return undef;
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

   if($output =~ /(.+):(\d+):.+:(.+)/om) {
      return undef;
   }
   elsif($output =~ /(.+):(\d+):.+/om) {
      $self->filePath($1);
   }

   return undef;
}

sub parseForLineNumber {
   my $self   = shift or die;
   my $output = shift or die;

   if($output =~ /(.+):(\d+):.+:(.+)/om) {
      return undef;
   }
   elsif($output =~ /(.+):(\d+):.+/om) {
      $self->lineNumber($2);
   }

   return undef;
}


1;
