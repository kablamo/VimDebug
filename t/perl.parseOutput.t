#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Vim::Debug::Perl;

my @tests = (
   {
      test       => "No match",
      string     => '11==>   my $rc = App::Cpan->run( @ARGV );\n 12     \n13      # Some comment.',
      filePath   => undef,
      lineNumber => undef,
   },
   {
      test       => "main::",
      string     => "main::(/opt/apps/perl/bin/cpan:9):",
      filePath   => '/opt/apps/perl/bin/cpan',
      lineNumber =>  9,
   },
   {
      test        => "Foo::meh",
      string      => "Foo::meh(/some/where/Foo.pm:353):",
      filePath    => '/some/where/Foo.pm',
      lineNumber  => 353,
   },
   {
      test        => "Multi line",
      string      => "foo\nmain::(/opt/apps/perl/bin/cpan:9):\nBar",
      filePath    => '/opt/apps/perl/bin/cpan',
      lineNumber  => 9,
   },
   {
      test        => "App::Cpan::run",
      string      => "App::Cpan::run(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:353):",
      filePath    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      lineNumber  => 353,
   },
   {
      test        => "App::Cpan::CODE(0xa3fd670)",
      string      => "App::Cpan::CODE(0xa3fd670)(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:459):",
      filePath    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      lineNumber  => 459,
   },
   {
      test        => "Another code ref", 
      string      => "Class::Foo::CODE(0xa1e4988)(accessor amount defined at lib/Currency.pm:8):",
      filePath    => 'lib/Currency.pm',
      lineNumber  => 8,
   },
);

my $v = Vim::Debug::Perl->new();

foreach my $t (@tests) {
    $v->parseOutput($t->{string});
    is($v->filePath,   $t->{filePath},   $t->{testName});
    is($v->lineNumber, $t->{lineNumber}, $t->{testName});
}

done_testing;

