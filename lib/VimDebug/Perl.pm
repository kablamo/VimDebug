# ABSTRACT: VimDebug Perl interface.
package VimDebug::Perl;

use strict;
use warnings;
use parent qw(VimDebug);
use Carp;

$ENV{"PERL5DB"}     = 'BEGIN {require "perl5db.pl";}';
$ENV{"PERLDB_OPTS"} = "ornaments=''";


# used to parse debugger 
our $dpr = '.*  DB<+\d+>+ '; # debugger prompt regex
sub dbgrPromptRegex    { qr/$dpr/ }
sub compilerErrorRegex { qr/aborted due to compilation error${dpr}/ }
sub runtimeErrorRegex  { qr/ at .* line \d+${dpr}/ }
sub appExitedRegex     { qr/((\/perl5db.pl:)|(Use .* to quit or .* to restart)|(\' to quit or \`R\' to restart))${dpr}/ }

sub parseOutput {
   my $self   = shift or confess;
   my $output = shift or confess;

   # take care of the problem case when we hit an eval() statement
   # example: main::function((eval 3)[debugTestCase.pl:5]:1):      my $foo = 1
   # this will turn that example debugger output into:
   #          main::function(debugTestCase.pl:5):      my $foo = 1
   if ($output =~  /\w*::(\w*)\(+eval\s+\d+\)+\[(.*):(\d+)\]:\d+\):/om) {
       $output =~ s/\w*::(\w*)\(+eval\s+\d+\)+\[(.*):(\d+)\]:\d+\):/::$1($2:$3):/m;
   }

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

   $output =~ /
      ^x .*\n(.*)
   /xm;
   $self->value($1)  if defined $1;

   return undef;
}

sub next                { return [ 'n'                  ] }
sub step                { return [ 's'                  ] }
sub cont                { return [ 'c'                  ] }
sub break               { return [ "f $_[2]", "b $_[1]" ] }
sub clear               { return [ "f $_[2]", "B $_[1]" ] }
sub clearAll            { return [ "B *"                ] }
sub print               { return [ "x $_[1]"            ] }
sub command             { return [ $_[1]                ] }
sub restart             { return [ "R"                  ] }
sub quit                { return [ "q"                  ] }


1;
