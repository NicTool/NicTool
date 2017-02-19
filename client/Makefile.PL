use strict;
use warnings;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  "ABSTRACT" => "CGI Interface to NicToolServer",
  "AUTHOR" => "Matt Simerson <msimerson\@cpan.org>, Damon Edwards, Abe Shelton, Greg Schueler",
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => 0
  },
  "DISTNAME" => "NicToolClient",
  "EXE_FILES" => [],
  "LICENSE" => "open_source",
  "NAME" => "NicToolClient",
  "PREREQ_PM" => {
    "CGI" => 3,
    "Data::Dumper" => 0,
    "JSON" => 0,
    "LWP::UserAgent" => 1,
    "RPC::XML" => 1,
    "RPC::XML::Parser" => 0,
    "SOAP::Lite" => 0,
    "XML::Parser" => 0,
    "strict" => 0,
    "vars" => 0
  },
  "TEST_REQUIRES" => {
    "English" => 0,
    "Test::More" => 0,
    "lib" => 0,
    "warnings" => 0
  },
  "VERSION" => "2.33",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "CGI" => 3,
  "Data::Dumper" => 0,
  "English" => 0,
  "ExtUtils::MakeMaker" => 0,
  "JSON" => 0,
  "LWP::UserAgent" => 1,
  "RPC::XML" => 1,
  "RPC::XML::Parser" => 0,
  "SOAP::Lite" => 0,
  "Test::More" => 0,
  "XML::Parser" => 0,
  "lib" => 0,
  "strict" => 0,
  "vars" => 0,
  "warnings" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
