
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "A client framework for interaction with a NicToolServer via SOAP or XML-RPC.",
  "AUTHOR" => "Matt Simerson <msimerson\@cpan.org>, Damon Edwards, Abe Shelton, Greg Schueler",
  "BUILD_REQUIRES" => {
    "English" => 0,
    "Test" => 0,
    "Test::More" => 0,
    "TestConfig" => 0,
    "warnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "NicTool",
  "EXE_FILES" => [],
  "LICENSE" => "open_source",
  "NAME" => "NicTool",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Data::Dumper" => 0,
    "LWP" => 0,
    "RPC::XML" => 1,
    "RPC::XML::Parser" => 0,
    "SOAP::Lite" => "0.51",
    "strict" => 0
  },
  "VERSION" => "1.02",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



