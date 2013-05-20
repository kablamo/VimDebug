# ABSTRACT: Perl wrapper around a command line debugger

=head1 SYNOPSIS

    package Vim::Debug;

    my $debugger = Vim::Debug->new(
        language => 'Perl',
        invoke   => 'perl -Ilib -d t/perl.pl 42',
    );

    $debugger->start;
    sleep(1) until $debugger->read;
    print "line:   " . $debugger->line . "\n";
    print "file:   " . $debugger->file . "\n";
    print "output: " . $debugger->output . "\n";

    $debugger->step;          sleep(1) until $debugger->read;
    $debugger->next;          sleep(1) until $debugger->read;
    $debugger->write('help'); sleep(1) until $debugger->read;

    $debugger->quit;

=head1 DESCRIPTION

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

Vim::Debug is an object oriented wrapper around the Perl command line
debugger. In theory the debugger could be for any language -- not just
Perl. But only Perl is supported currently.

The read() method is non blocking. This allows a user to send an
interrupt when they get stuck in an infinite loop.

=cut
package Vim::Debug;

# VERSION

use Carp;
use IO::Pty;
use IPC::Run;
use Moose ;
use Moose::Util qw(apply_all_roles);
use Vim::Debug::Protocol;

$| = 1;

my $READ;
my $WRITE;

    # Debugger statuses.
sub s_compilerError { Vim::Debug::Protocol->k_compilerError }
sub s_runtimeError  { Vim::Debug::Protocol->k_runtimeError }
sub s_appExited     { Vim::Debug::Protocol->k_appExited }
sub s_dbgrReady     { Vim::Debug::Protocol->k_dbgrReady }

=method language

The language that the debugger is made to handle. Currently, only
'Perl' is supported.

=method invoke

The string used to invoke the debugger, for example 'perl -Ilib -d
t/perl.pl 42',

=method stop

=method line

=method file

=method value

=method status

=cut

has invoke    => ( is => 'ro', isa => 'Str', required => 1 );
has language  => ( is => 'ro', isa => 'Str', required => 1 );

has stop      => ( is => 'rw', isa => 'Int' );
has line      => ( is => 'rw', isa => 'Int' );
has file      => ( is => 'rw', isa => 'Str' );
has value     => ( is => 'rw', isa => 'Str' );
has status    => ( is => 'rw', isa => 'Str' );

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
}

=method start()

Starts up the command line debugger in a separate process.

Returns $self.

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
            $self->_timer,
        )
    );
    return $self;
}

=method write($command)

Write $command to the debugger's stdin. This method blocks until the
debugger process reads. Be sure to include a newline.

Return value should be ignored.

=cut
sub write {
    my $self = shift or confess;
    my $c    = shift or confess;
    $self->value('');
    $self->stop(0);
    $WRITE .= "$c\n";
    return;
}

=method read()

Performs a non-blocking read on stdout from the debugger process.
read() first looks for a debugger prompt.

If none is found, the debugger isn't finished thinking so read()
returns 0.

If a debugger prompt is found, the output is parsed.  The following
information is parsed out and saved into attributes: line(), file(),
value(), and out().

read() will also send an interrupt (CTL+C) to the debugger process if
the stop() attribute is set to true.

=cut
# --------------------------------------------------------------------
sub read {
    my $self = shift or confess;

    $self->_timer->reset();
    eval { $self->_dbgr->pump_nb() };
    if ($@ =~ /process ended prematurely/) {
        undef $@;
        return 1;
    }
    elsif ($@) {
        die $@;
    }

    my $out = $READ;
    if ($self->stop) {
        $self->_dbgr->signal("INT");
        $self->_timer->reset();
        $self->_dbgr->pump() until $self->prompted_and_parsed($READ);
        $out = $READ;
    }
    $self->out($out);
    $self->prompted_and_parsed($self->out) || return 0;
    $self->_original($out);
    return 1;
}

=method out($out)

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

=method translate($in)

Translate protocol command $in to a native debugger command, returned
as an arrayref of strings.

Dies if no translation is found.

=cut
sub translate {
    my ($self, $in) = @_;
    my @cmds;

       if ($in =~ /^next$/            ) { @cmds = $self->next          }
    elsif ($in =~ /^step$/            ) { @cmds = $self->step          }
    elsif ($in =~ /^stepout$/         ) { @cmds = $self->stepout       }
    elsif ($in =~ /^cont$/            ) { @cmds = $self->cont          }
    elsif ($in =~ /^break:(\d+):(.+)$/) { @cmds = $self->break($1, $2) }
    elsif ($in =~ /^clear:(\d+):(.+)$/) { @cmds = $self->clear($1, $2) }
    elsif ($in =~ /^clearAll$/        ) { @cmds = $self->clearAll      }
    elsif ($in =~ /^print:(.+)$/      ) { @cmds = $self->print($1)     }
    elsif ($in =~ /^command:(.+)$/    ) { @cmds = $self->command($1)   }
    elsif ($in =~ /^restart$/         ) { @cmds = $self->restart       }
    elsif ($in =~ /^quit$/            ) { @cmds = $self->quit($1)      }
   # elsif ($in =~ /^(\w+):(.+)$/      ) { @cmds = $self->$1($2)        }
   # elsif ($in =~ /^(\w+)$/           ) { @cmds = $self->$1()          }
    else { die "ERROR 002.  Please email vimdebug at iijo dot org.\n"  }

    return \@cmds;
}

=method state()

Returns a hash (a list actually) whose keys are qw<stop line file
value status output>, and whose values are the corresponding values of
the object.

=cut
sub state {
    my $self = shift;
    return (
        stop   => $self->stop,
        line   => $self->line,
        file   => $self->file,
        value  => $self->value,
        status => $self->status,
        output => $self->out,
    );
}

=head1 SEE ALSO

L<Vim::Debug::Manual>, L<Vim::Debug::Perl>, L<Devel::ebug>, L<perldebguts>

=head1 BUGS

In retrospect its possible there is a better solution to this.  Perhaps
directly hooking directly into the debugger rather than using regexps to parse
stdout and stderr?

=cut
1;
