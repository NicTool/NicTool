use ExtUtils::MakeMaker;

WriteMakefile(
        NAME               => "NicTool::Bundle",
        VERSION_FROM       => "server/lib/NicToolServer.pm",
        AUTHOR             => 'Matt Simerson <msimerson@cpan.org>',
        ABSTRACT           => 'NicTool DNS Management suite',
        LICENSE            => 'open_source',
        #dist               => { COMPRESS => 'gzip -9f', },
        dist               => { COMPRESS => 'bzip2', SUFFIX => '.bz2' },
        'MIN_PERL_VERSION' => 5.008001,
        'BUILD_REQUIRES'   => {
                                'Dist::Zilla' => 0,
                              },
         PREREQ_PM         => {
                              },
         TEST_REQUIRES     => {
                              },
    );

sub MY::postamble {
    return <<'MAKE_FRAG'
bundle : server client
	tar -czf NicTool.tar.gz server/*.tar.gz client/*.tar.gz
	cd server; dzil clean
	cd client; dzil clean
	make distclean

server : server/NicToolServer.tar.gz

client : client/NicToolClient.tar.gz

server/NicToolServer.tar.gz :
	cd server; dzil clean; dzil build

client/NicToolClient.tar.gz :
	cd client; dzil clean; dzil build

web : NicTool.tar.gz
	scp NicTool.tar.gz www.nictool.com:/home/nictool.com/html/download/NicTool.tar.gz
	scp NicTool.tar.gz www.nictool.com:/home/nictool.com/html/download/NicTool-$(VERSION).tar.gz
MAKE_FRAG
;
}
