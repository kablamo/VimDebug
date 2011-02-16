#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use VimDebug::DebuggerInterface::Perl;

for my $t_ref (
   [
      "No match",
      '11==>   my $rc = App::Cpan->run( @ARGV );\n 12     \n13      # Some comment.',
   ],
   [
      "main::",
      "main::(/opt/apps/perl/bin/cpan:9):",
      qw<     /opt/apps/perl/bin/cpan 9 >,
   ],
   [
      "Foo::meh",
      "Foo::meh(/some/where/Foo.pm:353):",
      qw<       /some/where/Foo.pm 353 >,
   ],
   [
      "Multi line",
      "foo\nmain::(/opt/apps/perl/bin/cpan:9):\nBar",
      qw<          /opt/apps/perl/bin/cpan 9 >,
   ],
   [
      "App::Cpan::run",
      "App::Cpan::run(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:353):",
      qw<             /opt/apps/perl/lib/5.12.2/App/Cpan.pm 353 >,
   ],
   [
      "App::Cpan::CODE(0xa3fd670)",
      "App::Cpan::CODE(0xa3fd670)(/opt/apps/perl/lib/5.12.2/App/Cpan.pm:459):",
      qw<                         /opt/apps/perl/lib/5.12.2/App/Cpan.pm 459 >,
   ],
   [
      "Another code ref", 
      "Class::Foo::CODE(0xa1e4988)(accessor amount defined at lib/Currency.pm:8):",
      qw<                                                     lib/Currency.pm 8 >,
   ],
) {
    my ($test_name, $str, $exp_f, $exp_l) = @$t_ref;
    my ($got_f, $got_l) = VimDebug::DebuggerInterface::Perl::_getFileAndLine($str);
    is($got_f, $exp_f, $test_name);
    is($got_l, $exp_l, $test_name);
}

done_testing();

