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

use Carp;
use IO::Pty;
use IPC::Run;
use Moose ;
use Moose::Util qw(apply_all_roles);

$| = 1;

my $READ;
my $WRITE;

my $COMPILER_ERROR = "compiler error";
my $RUNTIME_ERROR  = "runtime error";
my $APP_EXITED     = "application exited";
my $DBGR_READY     = "debugger ready";

has invoke   => ( is => 'ro', isa => 'Str', required => 1 );
has language => ( is => 'ro', isa => 'Str', required => 1 );

has stop            => ( is => 'rw', isa => 'Int' );
has lineNumber      => ( is => 'rw', isa => 'Int' );
has filePath        => ( is => 'rw', isa => 'Str' );
has value           => ( is => 'rw', isa => 'Str' );
has status          => ( is => 'rw', isa => 'Str' );

has _timer    => ( is => 'rw', isa => 'IPC::Run::Timer' );
has _dbgr     => ( is => 'rw', isa => 'IPC::Run', handles => [qw(finish)] );
has _READ     => ( is => 'rw', isa => 'Str' );
has _WRITE    => ( is => 'rw', isa => 'Str' );
has _original => ( is => 'rw', isa => 'Str' );
has _out      => ( is => 'rw', isa => 'Str' );

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    my %args  = @_;

    if (defined $args{invoke} && $args{invoke} eq 'SCALAR') {
        $args{invoke} = [split(/\s+/, $args{invoke})];
        return $class->$orig(%args);
    }
    
    return $class->$orig(@_);
};

sub BUILD {
    my $self = shift;
    apply_all_roles($self, 'Vim::Debug::' . $self->language);
    $self->start;
}

=head2 start()

Starts up the command line debugger in a seperate process.

start() always returns undef.

=cut
sub start {
    my $self = shift or confess;

    $self->value('');
    $self->_out('');
    $self->_original('');
    $self->_timer(IPC::Run::timeout(10, exception => 'timed out'));

    my @cmd = split(qr/\s+/, $self->invoke);

    # spawn debugger process
    $self->_dbgr(
        IPC::Run::start(
          \@cmd, 
          '<pty<', \$WRITE,
          '>pty>', \$READ,
          $self->_timer
       )
    );

    return undef;
}

=head2 write($command)

Write $command to the debugger's stdin.  This method blocks until the debugger process
reads.  Be sure to include a newline.

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

   $self->_timer->reset();
   eval { $self->_dbgr->pump_nb() };
   my $out = $READ;

   if ($@ =~ /process ended prematurely/) {
       undef $@;
       return 1;
   }
   elsif ($@) {
       die $@;
   }

   if ($self->stop) {
       $self->_dbgr->signal("INT");
       $self->_timer->reset();
       $self->_dbgr->pump() until ($READ =~ /$dbgrPromptRegex/    || 
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

   $self->_original($out);
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

      my $originalLen = length $self->_original;
      $out = substr($out, $originalLen);
        
      # vim is not displaying newline characters correctly for some reason.
      # this localizes the newlines.
      $out =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;

      # save
      $self->_out($out);
   }

   return $self->_out;
}

=head2 translate($in)                                                                                                          
                                                                                                                               
Translate a protocol command ($in) to a native debugger command.  The native                                                   
debugger command is returned as an arrayref of strings.                                                                           
                                                                                                                               
Dies if no translation is found.                                                                                               
                                                                                                                               
=cut       
sub translate {
    my ($self, $in) = @_;
    my @cmds = ();

       if ($in =~ /^next$/            ) { @cmds = $self->next          }
    elsif ($in =~ /^step$/            ) { @cmds = $self->step          }
    elsif ($in =~ /^cont$/            ) { @cmds = $self->cont          }
    elsif ($in =~ /^break:(\d+):(.+)$/) { @cmds = $self->break($1, $2) }
    elsif ($in =~ /^clear:(\d+):(.+)$/) { @cmds = $self->clear($1, $2) }
    elsif ($in =~ /^clearAll$/        ) { @cmds = $self->clearAll      }
    elsif ($in =~ /^print:(.+)$/      ) { @cmds = $self->print($1)     }
    elsif ($in =~ /^command:(.+)$/    ) { @cmds = $self->command($1)   }
    elsif ($in =~ /^restart$/         ) { @cmds = $self->restart       }
    elsif ($in =~ /^quit$/            ) { @cmds = $self->quit($1)      }
#   elsif ($in =~ /^(\w+):(.+)$/      ) { @cmds = $self->$1($2)        }
#   elsif ($in =~ /^(\w+)$/           ) { @cmds = $self->$1()          }
    else { die "ERROR 002.  Please email vimdebug at iijo dot org.\n"  }

    return \@cmds;
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
