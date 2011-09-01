# ABSTRACT: Perl wrapper around a command line debugger

=head1 SYNOPSIS

If you are new to the Vim::Debug project please read the L<Vim::Debug::Manual> first.

    package Vim::Debug;

    my $debugger = Vim::Debug->new;
    $debugger->start;
    $debugger->write('s'); # step
    sleep(1) until $debugger->read;
    print $debugger->lineNumber;
    print $debugger->fileName;
    print $debugger->output;
    $debugger->write('q'); # quit
   

=head1 DESCRIPTION

The Vim::Debug project integrates the Perl debugger with Vim, allowing
developers to visually step through their code and examine variables.  

If you are new to the Vim::Debug project please read the L<Vim::Debug::Manual> first.

Please note that this code is in beta and these libraries will be changing
radically in the near future.

=head1 PREREQUISITES

Vim compiled with +signs and +perl.

=head1 INSTALL INSTRUCTIONS

Replace $VIMHOME with your vim configuration directory.  (/home/username/.vim on unix.)

=head2 With cpanm

    TODO

=head2 With github

    git clone git@github.com:kablamo/VimDebug.git
    cd VimDebug
    perl Makefile.PL
    make
    sudo make install
    cp -r vim/* $VIMHOME/

=head1 Vim::Debug

The Vim::Debug class provides an object oriented wrapper around the Perl
command line debugger.  

Note that the read() method is non blocking. 

=head1 FUNCTIONS

=cut

package Vim::Debug;

use strict;
use warnings;
use Class::Accessor::Fast;
use base qw(Class::Accessor::Fast);

use Carp;
use IO::Pty;
use IPC::Run;

$| = 1;

my $READ;
my $WRITE;

my $COMPILER_ERROR = "compiler error";
my $RUNTIME_ERROR  = "runtime error";
my $APP_EXITED     = "application exited";
my $DBGR_READY     = "debugger ready";

__PACKAGE__->mk_accessors(
    qw(dbgrCmd timer dbgr stop shutdown lineNumber filePath value translatedInput READ WRITE
       debug original status oldOut)
);

=head2 start()

Starts up the command line debugger in a seperate process.

start() always returns undef.

=cut
sub start {
   my $self = shift or confess;

   # initialize some variables
   $self->original('');
   $self->out('');
   $self->value('');
   $self->oldOut('');
   $self->translatedInput([]);
   $self->debug(0);
   $self->timer(IPC::Run::timeout(10, exception => 'timed out'));

   # spawn debugger process
   $self->dbgr(
      IPC::Run::start(
         $self->dbgrCmd, 
         '<pty<', \$WRITE,
         '>pty>', \$READ,
         $self->timer
      )
   );
   return undef;
}

=head2 write($command)

Write $command to the debugger's stdin.  This method blocks until the debugger process
reads.  Be ssure to include a newline.

write() always returns undef;

=cut
sub write {
   my $self = shift or confess;
   my $c    = shift or confess;
   $self->value('');
   $self->stop(0);
   $WRITE .= "$c\n";
   return;
}

=head2 read()

Performs a nonblocking read on stdout from the debugger process.  read() first
looks for a debugger prompt.  

If one is not found, the debugger isn't finished thinking so read() returns 0.   

If a debugger prompt is found, the output is parsed.  The following
information is parsed out and saved into attributes: lineNumber(), fileName(),
value(), and out().

read() will also send an interrupt (CTL+C) to the debugger process if the
stop() attribute is set to true.

=cut
sub read {
   my $self = shift or confess;
   $| = 1;

   my $dbgrPromptRegex    = $self->dbgrPromptRegex;
   my $compilerErrorRegex = $self->compilerErrorRegex;
   my $runtimeErrorRegex  = $self->runtimeErrorRegex;
   my $appExitedRegex     = $self->appExitedRegex;

   $self->timer->reset();
   eval { $self->dbgr->pump_nb() };
   my $out = $READ;

   if ($@ =~ /process ended prematurely/) {
       print "::read(): process ended prematurely\n" if $self->debug;
       undef $@;
       return 1;
   }
   elsif ($@) {
       die $@;
   }

   if ($self->stop) {
       print "::read(): stopping\n" if $self->debug;
       $self->dbgr->signal("INT");
       $self->timer->reset();
       $self->dbgr->pump() until ($READ =~ /$dbgrPromptRegex/    || 
                                  $READ =~ /$compilerErrorRegex/ || 
                                  $READ =~ /$runtimeErrorRegex/  || 
                                  $READ =~ /$appExitedRegex/); 
       $out = $READ;
   }

   $self->out($out);

   if    ($self->out =~ $dbgrPromptRegex)    { $self->status($DBGR_READY)     }
   elsif ($self->out =~ $compilerErrorRegex) { $self->status($COMPILER_ERROR) }
   elsif ($self->out =~ $runtimeErrorRegex)  { $self->status($RUNTIME_ERROR)  }
   elsif ($self->out =~ $appExitedRegex)     { $self->status($APP_EXITED)     }
   else                                      { return 0                       }

   $self->original($out);
   $self->parseOutput($self->out);

   return 1;
}

=head2 out($out)

If called with a parameter, out() removes ornaments (like <CTL-M> or
irrelevant error messages or whatever) from text and saves the value.

If called without a parameter, out() returns the saved value.

=cut
sub out {
   my $self = shift or confess;
   my $out = '';

   if (@_) {
      $out = shift;

      my $originalLen = length $self->original;
      $out = substr($out, $originalLen);
        
      # vim is not displaying newline characters correctly for some reason.
      # this localizes the newlines.
      $out =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;

      # save
      $self->{out} = $out;
   }

   return $self->{out};
}

=head2 lineNumber($number)

If $number parameter is used, the lineNumber class attribute is set using that
value.  If no parameters are passed, the current value of the lineNumber 
attribute is returned.

=head2 filePath($path)

If $path parameter is used, the filePath class attribute is set using that
value.  If no parameters are passed, the current value of the filePath 
attribute is returned.

=head2 dbgrPromptRegex($regex)

If $regex parameter is used, the dbgrPromptRegex class attribute is set using that
value.  If no parameters are passed, the current value of the dbgrPromptRegex 
attribute is returned.


=head1 SEE ALSO

L<Devel::ebug>, L<perldebguts>


=head1 AUTHOR

Eric Johnson, cpan at iijo : :dot: : org

=head1 COPYRIGHT

Copyright (C) 2003 - 3090, Eric Johnson

This module is GPL.

=cut

1;
