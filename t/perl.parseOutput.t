#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Vim::Debug;

my @tests = (
   {
      test    => "No match",
      string  => '11==>   my $rc = App::Cpan->run( @ARGV );\n 12     \n13      # Some comment.',
      file    => undef,
      line    => undef,
   },
   {
      test    => "main::",
      string  => "main::(/opt/apps/perl/bin/cpan:9):",
      file    => '/opt/apps/perl/bin/cpan',
      line    =>  9,
   },
   {
      test    => "Foo::meh",
      string  => "Foo::meh(/some/where/Foo.pm:353):",
      file    => '/some/where/Foo.pm',
      line    => 353,
   },
   {
      test    => "Multi line",
      string  => "foo\nmain::(/opt/apps/perl/bin/cpan:9):\nBar",
      file    => '/opt/apps/perl/bin/cpan',
      line    => 9,
   },
   {
      test    => "App::Cpan::run",
      string  => "App::Cpan::run(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:353):",
      file    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      line    => 353,
   },
   {
      test    => "App::Cpan::CODE(0xa3fd670)",
      string  => "App::Cpan::CODE(0xa3fd670)(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:459):",
      file    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      line    => 459,
   },
   {
      test    => "Another code ref", 
      string  => "Class::Foo::CODE(0xa1e4988)(accessor amount defined at lib/Currency.pm:8):",
      file    => 'lib/Currency.pm',
      line    => 8,
   },
);

my $debugger = Vim::Debug->new(language => 'Perl', invoke => 'foo');

foreach my $t (@tests) {
    $debugger->parseOutput($t->{string});
    is($debugger->file, $t->{file},   $t->{testName});
    is($debugger->line, $t->{line}, $t->{testName});
}

done_testing;

