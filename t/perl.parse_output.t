#!perl

use strict;
use warnings;

use Test::More;
use Vim::Debug;

my @tests = (
   {
      test_id => "No match",
      string  => '11==>   my $rc = App::Cpan->run( @ARGV );\n 12     \n13      # Some comment.',
      file    => '',
      line    => 0,
   },
   {
      test_id => "main::",
      string  => "main::(/opt/apps/perl/bin/cpan:9):",
      file    => '/opt/apps/perl/bin/cpan',
      line    =>  9,
   },
   {
      test_id => "Foo::meh",
      string  => "Foo::meh(/some/where/Foo.pm:353):",
      file    => '/some/where/Foo.pm',
      line    => 353,
   },
   {
      test_id => "Multi line",
      string  => "foo\nmain::(/opt/apps/perl/bin/cpan:9):\nBar",
      file    => '/opt/apps/perl/bin/cpan',
      line    => 9,
   },
   {
      test_id => "App::Cpan::run",
      string  => "App::Cpan::run(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:353):",
      file    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      line    => 353,
   },
   {
      test_id => "App::Cpan::CODE(0xa3fd670)",
      string  => "App::Cpan::CODE(0xa3fd670)(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:459):",
      file    => '/opt/apps/perl/lib/5.12.2/App/Cpan.pm',
      line    => 459,
   },
   {
      test_id => "Another code ref",
      string  => "Class::Foo::CODE(0xa1e4988)(accessor amount defined at lib/Currency.pm:8):",
      file    => 'lib/Currency.pm',
      line    => 8,
   },
);

my $debugger = Vim::Debug->new(
    language => 'Perl',
    filename => 'dont_care',
    arguments => '',
);

foreach my $t (@tests) {
    $debugger->_parse_output($t->{string});
    is($debugger->file, $t->{file}, $t->{test_id});
    is($debugger->line, $t->{line}, $t->{test_id});
}

done_testing;

