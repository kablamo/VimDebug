# ABSTRACT: Perl debugger interface.

=head1 SYNOPSIS

If you are new to the Vim::Debug project please read the L<Vim::Debug::Manual> first.

    package Vim::Debug::Perl

    my $debugger = Vim::Debug::Perl->new;
    $debugger->next;
    $debugger->step;
   

=head1 DESCRIPTION

This module inherits from Vim::Debug.  See that module for a more in depth
explanation.  This module only handles the Perl specific bits.

=cut

package Vim::Debug::Perl;

use strict;
use warnings;
use parent qw(Vim::Debug);
use Carp;

$ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
$ENV{"PERLDB_OPTS"} = "ornaments=''";



=head1 DEBUGGER OUTPUT REGEX CLASS ATTRIBUTES

These attributes are used to parse debugger output and are used by Vim::Debug.
They return a regex and ignore all values passed to them.  

=head2 dbgrPromptRegex()

=head2 compilerErrorRegex()

=head2 runtimeErrorRegex()

=head2 appExitedRegex()

=cut

our $dpr = '.*  DB<+\d+>+ '; # debugger prompt regex
sub dbgrPromptRegex    { qr/$dpr/ }
sub compilerErrorRegex { qr/aborted due to compilation error${dpr}/ }
sub runtimeErrorRegex  { qr/ at .* line \d+${dpr}/ }
sub appExitedRegex     { qr/((\/perl5db.pl:)|(Use .* to quit or .* to restart)|(\' to quit or \`R\' to restart))${dpr}/ }

=head1 TRANSLATION CLASS ATTRIBUTES

These attributes are used by Vim::Debug::Daemon to convert commands from the
communication protocol to commands the Perl debugger can recognize.  For
example, the communication protocol uses the keyword 'next' while the Perl
debugger uses 'n'.

=head2 next()

=head2 step()

=head2 cont()

=head2 break()

=head2 clear()

=head2 clearAll()

=head2 print()

=head2 command()

=head2 restart()

=head2 quit()

=cut

sub next                { return ( 'n'                  ) }
sub step                { return ( 's'                  ) }
sub cont                { return ( 'c'                  ) }
sub break               { return ( "f $_[2]", "b $_[1]" ) }
sub clear               { return ( "f $_[2]", "B $_[1]" ) }
sub clearAll            { return ( "B *"                ) }
sub print               { return ( "x $_[1]"            ) }
sub command             { return ( $_[1]                ) }
sub restart             { return ( "R"                  ) }
sub quit                { return ( "q"                  ) }

=head2 METHODS

=cut

=head2 parseOutput($output)

$output is output from the Perl debugger.  This method parses $output and
saves relevant valus to the lineNumber, filePath, and output attributes (these
attributes are defined in Vim::Debug)

Returns undef.

=cut
sub parseOutput {
   my $self   = shift or confess;
   my $output = shift or confess;

   {
      # See .../t/VD_DI_Perl.t for test cases.
      my $filePath;
      my $lineNumber;
      $output =~ /
         ^ \w+ ::
         (?: \w+ :: )*
         (?: CODE \( 0x \w+ \) | \w+ )?
         \(
            (?: .* \x20 )?
            ( .+ ) : ( \d+ )
         \):
      /xm;
      $self->filePath($1)   if defined $1;
      $self->lineNumber($2) if defined $2;
   }

   {
      if ($output =~ /^x .*\n/m) {
         $output =~ s/^x .*\n//m; # remove first line
         $output =~ s/\n.*$//m; # remove last line
         $self->value($output);
      }
   }

   return undef;
}

1;
