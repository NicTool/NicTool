use ExtUtils::MakeMaker;

WriteMakefile(
        NAME               => "NicTool::Bundle",
        VERSION_FROM       => "server/lib/NicToolServer.pm",
        AUTHOR             => 'Matt Simerson <msimerson@cpan.org>',
        ABSTRACT           => 'NicTool DNS Management suite',
        LICENSE            => 'open_source',
        dist               => { COMPRESS => 'gzip -9f', },
        'MIN_PERL_VERSION' => 5.008001,
        'BUILD_REQUIRES'   => {
                                'Dist::Zilla' => 0,
                 },
    );
