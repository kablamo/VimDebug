# ABSTRACT: Perl wrapper around a command line debugger
package Vim::Debug;
# VERSION

=head1 SYNOPSIS

    package Vim::Debug;

        # This will apply the roles found in Vim::Debug::Perl.
    my $VD = Vim::Debug->new(
        language => 'Perl',
    );
        # If all went well, the status should be 'stopped'.
    $VD->status eq 'stopped' or ...

        # start() returns an empty string if there was no error, else
        # an error message.
    my $error = $VD->start(
        filename => $some_perl_file,
        arguments => '42 qwerty',
    );
    ...

        # translate() obtains the exact commands to write to the
        # debugger. Most commands expand to a single element, but
        # some, like "break...", need two, We must read() between each
        # write() command.
    for my $cmd (@{$VD->translate('next')}) {
        $VD->write($cmd);
        sleep 1 until $VD->read;
    }

        # What we can learn after read().
    for my $query (qw<status file line result output>) {
        printf "$what: %s\n", $VD->$what;
    }

        # After this, we may want to start() again.
    $VD->stop;

=head1 DESCRIPTION

Vim::Debug is an object oriented wrapper around a command line
debugger. In theory the debugger could be for any language, but
only Perl is currently supported.

A Vim::Debug instance has a status(), which is initially 'stopped'. A
successful start($filename, $args) will have launched a debugger
session, and status() will then normally show 'ready'. We can now
write() to the debugger commands that it understands, normally
obtained through translate(). After a write(), we must wait until a
read() (non-blocking) succeeds before attempting another write(). If
read() keeps failing, we may attempt to interrupt() the debugger and
resume read() afterwards.

The role class, Vim::Debug::Perl for example, must implement these
methods:

=over 4

=item launch()

Returns a string to invoke the debugger. For example, for Perl we have:

    sub launch { 'perl -d -Ilib' }

=item respond($accum_dbgr_output)

Looks at the accumulated debugger output and if there is sufficient
data (usually denoted by the presence of the debugger prompt), parses
it into the file(), line(), result(), and output() attributes and
returns true. Else returns false.

=item translations()

Returns a hash ref whose keys are names of actions a debugger should
know how to respond to and the corresponding value, a sub ref that
returns a list of command strings write() to the debugger; after
each of these commands is written, a read() should eventually be made
to succeed (keep trying!) before writing the next.

For example, for Vim::Debug::Perl we have something like:

    sub translations {
        return +{
            next     => sub { 'n' },
            break    => sub { "f $_[1]", "b $_[0]" },
            ...
        }
    }

Vim::Debug::translate() is made to handle for example
'break:foo.pl:42' by calling

    $self->translations->{break}->(42, "foo.pl")

which will return the list ("f foo.pl", "b 42") to write() to the
debugger.

There must be translations for the following commands:

    next
    stepin
    stepout
    cont
    break
    clear
    clearAll
    print
    command
    restart

=back

=cut
use IPC::Run;
use Moose;
use Moose::Util qw(apply_all_roles);
use Moose::Util::TypeConstraints;

=attr language

The language that the debugger is made to handle. Currently, only
'Perl' is supported.

=attr filename

The file that is to be debugged.

=attr arguments

A string representing arguments that will be passed to the program
being debugged, as if from the command line.

=attr status

Debugger status (an enum of strings). Current possible values:

    filename_not_found
    cant_ipc_run
    bad_file
    stopped
    running
    ready
    compiler_error
    runtime_error
    app_exited

=cut
has language  => ( is => 'ro', isa => 'Str', required => 1 );

has filename  => ( is => 'rw', isa => 'Str', default => '' );

has arguments => ( is => 'rw', isa => 'Str', default => '' );

has status => (
    is => 'rw',
    isa => enum([qw<
        filename_not_found
        cant_ipc_run
        bad_file
        stopped
        running
        ready
        compiler_error
        runtime_error
        app_exited
    >]),
    default => 'stopped',
);

=attr file

The file that the debugger is currently in.

=attr line

The line at which the debugger currently is.

=attr result

The result parsed out of the last response from the debugger.

=attr output

All of the text obtained as the last response from the debugger.

=cut
has file   => ( is => 'rw', isa => 'Str', default => "" );
has line   => ( is => 'rw', isa => 'Int', default => 0 );
has result => ( is => 'rw', isa => 'Str', default => "" );
has output => ( is => 'rw', isa => 'Str', default => "" );

    # To accumulate read debugger output.
has _accum => ( is => 'rw', isa => 'Str' );
has _timer => ( is => 'rw', isa => 'IPC::Run::Timer' );
has _dbgr  => ( is => 'rw', isa => 'IPC::Run' );

my $READ;
my $WRITE;

=method new(language => $language)

Returns a Vim::Debug reference, applying roles from Vim::Debug::Perl
for example when $language is 'Perl'.

Only language 'Perl' is currently supported.

=cut
sub BUILD {
    my $self = shift;
    apply_all_roles($self, 'Vim::Debug::' . $self->language);
}

=method start($filename, $arguments)

Starts up the command line debugger in a separate process.

If successful, sets $self->status to 'running' and returns an empty
string, else returns $self->status.

If successful, you should now read() until successful, to parse out the
initial debugger output.

=cut
sub start {
    my ($self, $filename, $arguments) = @_;

    $self->filename($filename // '');
    $self->arguments($arguments // '');

        # Initialize.
    $self->status('stopped');
    $self->file('');
    $self->line(0);
    $self->result('');
    $self->output('');

    if (! -f $filename) {
        return $self->status('filename_not_found');
    }

        # Spawn the debugger process.
    $self->_timer(IPC::Run::timeout(10, exception => 'timed out'));
    if (
        my $spawn = IPC::Run::start(
            [split qr/\s+/, join(" ", $self->launch, $self->filename, $self->arguments)],
            '<pty<', \$WRITE,
            '>pty>', \$READ,
            $self->_timer,
        )
    ) {
        $self->_dbgr($spawn);
        $self->status('running');
        $self->_accum('');
        return '';
    }
    else {
        return $self->status('cant_ipc_run');
    }

}

=method interrupt()

Send the debugger an interrupt signal.

=cut
sub interrupt {
    my $self = shift;
    $self->_dbgr->signal("INT");
}

=method stop()

Stop the debugger.

=cut
sub stop {
    my ($self) = @_;
    $self->_dbgr->signal("TERM");
    $self->_dbgr->finish;
    $self->status("stopped");
}

=method translate($in)

Translate protocol command $in to a native debugger command, returned
as an arrayref of strings.

Returns undef if no translation is found.

=cut
sub translate {
    my ($self, $in) = @_;
    my $func =
        $in =~ /^next$/             ? 'next' :
        $in =~ /^stepin$/           ? 'stepin' :
        $in =~ /^stepout$/          ? 'stepout' :
        $in =~ /^cont$/             ? 'cont' :
        $in =~ /^break:(\d+):(.+)$/ ? 'break':
        $in =~ /^clear:(\d+):(.+)$/ ? 'clear':
        $in =~ /^clearAll$/         ? 'clearAll' :
        $in =~ /^print:(.+)$/       ? 'print' :
        $in =~ /^command:(.+)$/     ? 'command' :
        $in =~ /^restart$/          ? 'restart' :
        undef;

    return undef unless $func;
    return [$self->translations->{$func}->($1, $2)];
}

=method write($command)

Write an already translated $command to the debugger's stdin. Blocks
until the debugger process reads. Be sure to include a newline.

Return value should be ignored.

=cut
sub write {
    my ($self, $cmd) = @_;
    $self->result('');
    $WRITE .= "$cmd\n";
}

=method read()

Performs a non-blocking read on stdout from the debugger process.
read() first looks for a debugger prompt. If none is found, the
debugger isn't finished thinking so read() returns false. If a
debugger prompt is found, the output is parsed and saved into
attributes result(), status(), file(), line(), and read() returns
true.

=cut
sub read {
    my ($self) = @_;

    $self->_timer->reset;
    eval { $self->_dbgr->pump_nb };
    if ($@ =~ /process ended prematurely/) {
        undef $@;
        return 1;
    }
    elsif ($@) {
        die $@;
    }

    my $dbgr_output = $READ;
        # Normalize newlines, for Vim in particular.
    $dbgr_output =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;

    $self->_accum($self->_accum . $dbgr_output);
    $READ = '';
    if ($self->respond($self->_accum)) {
        $self->_accum('');
        return 1;
    }
    return;
}

=head1 SEE ALSO

L<Vim::Debug::Manual>, L<Vim::Debug::Perl>, L<Devel::ebug>,
L<perldebguts>

=head1 BUGS

In retrospect it's possible there is a better solution to this.
Perhaps directly hooking directly into the debugger rather than using
regexps to parse stdout and stderr?

=cut
1;

