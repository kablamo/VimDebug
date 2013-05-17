# ABSTRACT: Perl debugger interface.

=head1 DESCRIPTION

If you are new to Vim::Debug please read the user manual,
L<Vim::Debug::Manual>, first.

This module is a role that is dynamically applied to an Vim::Debug instance.
L<Vim::Debug> represents a debugger.  This module only handles the Perl
specific bits.  Theoretically there might be a Ruby or Python role someday.

=cut
package Vim::Debug::Perl;

# VERSION

use Moose::Role;

$ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
$ENV{"PERLDB_OPTS"} = "ornaments=''";

=head1 TRANSLATION CLASS ATTRIBUTES

These attributes are used to convert commands from the communication
protocol to commands the Perl debugger can recognize.  For example,
the communication protocol uses the keyword 'next' while the Perl
debugger uses 'n'.

=func next()

=func step()

=func cont()

=func break()

=func clear()

=func clearAll()

=func print()

=func command()

=func restart()

=func quit()

=cut
sub next     { 'n' }
sub step     { 's' }
sub cont     { 'c' }
sub break    { "f $_[2]", "b $_[1]" }
sub clear    { "f $_[2]", "B $_[1]" }
sub clearAll { 'B *' }
sub print    { "x $_[1]" }
sub command  { $_[1] }
sub restart  { 'R' }
sub quit     { 'q' }

=method prompted_and_parsed($output)

If the $output string doesn't end with the debugger prompt string,
this method will return false, because that means that there should be
more debugger output coming.

Otherwise, $output will be parsed and the object's 'file', 'line',
'value', and 'status' attributes will be set and the method will
return true.

=cut
    # Debugger prompt regex.
my $dpr = qr/  DB<+\d+>+ \z/s;

sub prompted_and_parsed {
    my ($self, $str) = @_;

        # If we don't have the debugger prompt string, we're not ready
        # to parse.
    return unless $str =~ s/$dpr//;

    $self->parseOutput($str);
    return 1;
}

sub parseOutput {
    my ($self, $str) = @_;

    my $file;
    my $line;
    my $status;

    if (
        $str  =~ /
            ^ Execution\ of\ .*?\ aborted\ due\ to\ compilation\ errors\.
            \n \ at\ (.*?)\ line\ (\d+)\.
        /xm
    ) {
        $status = $self->s_compilerError;
        $file = $1;
        $line = $2;
    }
    elsif (
        $str =~ /
            (?:
                (?: \/perl5db.pl: ) |
                (?: Use\ .*\ to\ quit\ or\ .*\ to\ restart ) |
                (?: '\ to\ quit\ or\ `R'\ to\ restart )
            )
        /sx
    ) {
        $status = $self->s_appExited;
    }
    else {
        $status = $self->s_dbgrReady;
        $str =~ /
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
            # the text remaining being the value that was requested.
        if ($str =~ /^x .*\n/m) {
            $str =~ s/^x .*\n//m;
            $str =~ s/\n.*$//m;
            $self->value($str);
        }
    }
    $self->file($file) if $file;
    $self->line($line) if $line;
    $self->status($status);
}

1;
