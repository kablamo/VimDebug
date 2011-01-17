use ExtUtils::MakeMaker;


WriteMakefile(
   NAME         => 'VimDebug',
   AUTHOR       => 'Eric Johnson <perl at nospamthanks.iijo.nospamno.org>',
   VERSION_FROM => 'VERSION',
   EXE_FILES    => ['bin/vdd','bin/vddTester'],
   PREREQ_PM    => {
      'File::Which'  => 0,
      'Getopt::Long' => 0,
      'IPC::Run'     => 0,
      'Test::Class'  => 0,
      'Test::More'   => 0,
   },
   dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
   clean        => { FILES => 'VimDebug-*' },
);


sub MY::postamble {

	if (getpwuid($<) =~ /^root/) {
		return '

installvim :
	$(CP) vim/plugin/*.vim /usr/share/vim/vimfiles/plugin/
	$(CP) vim/doc/*.txt    /usr/share/vim/vimfiles/doc/

		';
	}

   return '

installvim :
	$(CP) vim/plugin/*.vim $(HOME)/.vim/plugin/
	$(CP) vim/doc/*.txt    $(HOME)/.vim/doc/

installvim_windows :
	$(CP) vim\plugin\*.vim $(VIM)\vimfiles\plugin\
	$(CP) vim\doc\*.txt    $(VIM)\vimfiles\doc\

';
}


# vim: noexpandtab: shiftwidth=3: tabstop=3:
