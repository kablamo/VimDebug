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


package VimDebug::DebuggerInterface::Gdb;

use strict;
use warnings 'FATAL' => 'all';

use Carp;
use base qw(VimDebug::DebuggerInterface::Base);


# set some global variables

our $dbgrPath           = "gdb";
my  $dbgrPromptRegex    = '(\(gdb\) )|(y\? \(y or n\) )';

# callback functions implemented

sub startDebugger {
   my $self               = shift or die;
   my $path               = shift or die;
   my @commandLineOptions = @_;

   $path =~ s/(\.[^\.]+)$//;

   my   @incantation = $dbgrPath;
   push(@incantation, $path);
   push(@incantation, "-f");
   push(@incantation, @commandLineOptions);

   # this regexe aids in parsing debugger output.
   $self->dbgrPromptRegex($dbgrPromptRegex);
   $self->SUPER::_startDebugger(\@incantation);
   $self->SUPER::_command("start");

   return undef;
}

sub next {
   my $self = shift or die;
   $self->SUPER::_command("next");
   return undef;
}

sub step {
   my $self = shift or die;
   $self->SUPER::_command("step");
   return undef;
}

sub cont {
   my $self = shift or die;
   $self->SUPER::_command("continue");
   return undef;
}

sub setBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   $self->SUPER::_command("break $fileName:$lineNumber");

   return $lineNumber;
}

sub clearBreakPoint {
   my $self       = shift or die;
   my $lineNumber = shift or die;
   my $fileName   = shift or die;

   $self->SUPER::_command("clear $fileName:$lineNumber");

   return undef;
}

sub clearAllBreakPoints {
   my $self = shift or die;
   return $self->SUPER::_command("delete breakpoints");
   return undef;
}

sub printExpression {
   my $self       = shift or die;
   my $expression = shift or die;
   return $self->SUPER::_command("print $expression");
}

sub command {
   my $self = shift or die;
   my $command = shift or die;
   return $self->SUPER::_command($command);
}
 
sub restart {
   my $self = shift or die;
   $self->SUPER::_command("run");
   $self->SUPER::_command("y");
   return undef;
}

sub quit {
   my $self = shift or die;
   $self->SUPER::_command("q");
   $self->SUPER::_command("y");
   $self->dbgr->finish();
   return undef;
}

sub parseForFilePath {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /\W+(.+)\:(\d+)\:\d+\:\w+\:/om)  {
      $self->filePath($1);
   }
   return undef;
}

sub parseForLineNumber {
   my $self   = shift or die;
   my $output = shift or die;
   if ($output =~ /\W+(.+)\:(\d+)\:\d+\:\w+\:/om)  {
      $self->lineNumber($2);
   }
   return undef;
}

sub output {
   my $self = shift or die;
   my $output;

   if (@_) {
      $output = shift;
   print ">>>$output<<<\n";
      $output =~ s/\[tcsetpgrp\s+failed\s+in\s+terminal_inferior\:\s+Inappropriate\s+ioctl\s+for\s+device\]\s*//mg;
   print ":::output:::\n";
      $output =~ s/\[tcsetpgrp failed in terminal_inferior\: Inappropriate ioctl for device\]\s*\n//mg;
      $output =~ s///m;
      return $self->SUPER::output($output);
   }
   else {
      return $self->SUPER::output();
   }
}


1;
