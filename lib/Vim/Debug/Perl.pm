# ABSTRACT: Perl debugger interface.
package Vim::Debug::Perl;
# VERSION

=head1 DESCRIPTION

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

This module is a role that is dynamically applied to an Vim::Debug instance.
L<Vim::Debug> represents a debugger.  This module only handles the Perl
specific bits.  Theoretically there might be a Ruby or Python role someday.

=cut
use Moose::Role;

$ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
$ENV{"PERLDB_OPTS"} = "ornaments=''";

=head1 TRANSLATION METHODS

=cut
sub translations {
    return +{
        next     => sub { 'n' },
        stepin   => sub { 's' },
        stepout  => sub { 'r' },
        cont     => sub { 'c' },
        break    => sub { "f $_[1]", "b $_[0]" },
        clear    => sub { "f $_[1]", "B $_[0]" },
        clearAll => sub { 'B *' },
        print    => sub { "x $_[0]" },
        command  => sub { $_[0] },
        restart  => sub { 'R' },
    };
}

sub launch { 'perl -d -Ilib' }

=method respond($dbgr_output)

If the $dbgr_output string doesn't end with the debugger prompt
string, this method will return false, because that means that there
should be more debugger output coming.

Otherwise, $dbgr_output will be parsed and the object's 'result',
'status', 'file', and 'line', attributes will be set and the method
will return true.

=cut
    # Debugger prompt regex.
my $dpr = qr/  DB<+\d+>+ \z/s;

sub respond {
    my ($self, $dbgr_output) = @_;

        # If we don't have the debugger prompt string, we're not ready
        # to parse yet.
    return unless $dbgr_output =~ s/$dpr//;

    $self->_parse_output($dbgr_output);
    return 1;
}

sub _parse_output {
    my ($self, $dbgr_output) = @_;

    $self->output($dbgr_output);

    my $result = '';
    my $status = "unknown";
    my $file;
    my $line;

    if (
        $dbgr_output  =~ /
            ^ Execution\ of\ .*?\ aborted\ due\ to\ compilation\ errors\.
            \n \ at\ (.*?)\ line\ (\d+)\.
        /xm
    ) {
        $status = "compiler_error";
        $file = $1;
        $line = $2;
    }
    elsif (
        $dbgr_output =~ /
            (?:
                (?: \/perl5db.pl: ) |
                (?: Use\ .*\ to\ quit\ or\ .*\ to\ restart ) |
                (?: '\ to\ quit\ or\ `R'\ to\ restart )
            )
        /sx
    ) {
        $status = "app_exited";
    }
    else {
        $status = "ready";
        $dbgr_output =~ /
            ^ \w+ ::
            (?: \w+ :: )*
            (?: CODE \( 0x \w+ \) | \w+ )?
            \(
                (?: .* \x20 )?
                ( .+ ) : ( \d+ )
            \):
        /xm;
        $file = $1;
        $line = $2;

            # Remove first and last lines when 'x' was the command,
            # the text remaining being the result we want.
        if ($dbgr_output =~ /^x .*\n/m) {
            ($result = $dbgr_output) =~ s/^x .*\n//m;
            $result =~ s/\n.*$//m;
        }
    }
    $self->result($result);
    $self->status($status);
    $self->file($file) if $file;
    $self->line($line) if $line;
}

1;

