use strict;
use warnings;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  "ABSTRACT" => "NicTool API reference server",
  "AUTHOR" => "Matt Simerson <msimerson\@cpan.org>, Damon Edwards, Abe Shelton, Greg Schueler",
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => 0
  },
  "DISTNAME" => "NicToolServer",
  "EXE_FILES" => [],
  "LICENSE" => "open_source",
  "NAME" => "NicToolServer",
  "PREREQ_PM" => {
    "Apache::DBI" => 0,
    "BIND::Conf_Parser" => 0,
    "CGI" => 3,
    "Crypt::KeyDerivation" => 0,
    "Crypt::Mac::HMAC" => 0,
    "CryptX" => "0.021",
    "Cwd" => 0,
    "DBD::mysql" => "2.0416",
    "DBI" => "1.20",
    "DBIx::Simple" => 0,
    "Data::Dumper" => 0,
    "English" => 0,
    "File::Copy" => 0,
    "File::Path" => 0,
    "IO::File" => 0,
    "JSON" => 0,
    "LWP::UserAgent" => 0,
    "MIME::Base32" => 0,
    "MIME::Base64" => 0,
    "Net::DNS::ZoneFile" => 0,
    "Net::IP" => 0,
    "Params::Validate" => "0.8",
    "RPC::XML" => 0,
    "RPC::XML::Parser" => 0,
    "SOAP::Lite" => "0.51",
    "Scalar::Util" => 0,
    "Time::HiRes" => "1.9",
    "Time::Local" => 0,
    "Time::TAI64" => 2,
    "XML::Parser" => 0,
    "constant" => 0,
    "lib" => 0,
    "parent" => "0.2",
    "strict" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "TEST_REQUIRES" => {
    "Exporter" => 0,
    "Test" => 0,
    "Test::More" => 0,
    "Test::Output" => 0
  },
  "VERSION" => "2.33",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "APR::Table" => 0,
  "Apache::DBI" => 0,
  "BIND::Conf_Parser" => 0,
  "CGI" => 3,
  "Crypt::KeyDerivation" => 0,
  "Crypt::Mac::HMAC" => 0,
  "CryptX" => "0.021",
  "Cwd" => 0,
  "DBD::mysql" => "2.0416",
  "DBI" => "1.20",
  "DBIx::Simple" => 0,
  "Data::Dumper" => 0,
  "English" => 0,
  "Exporter" => 0,
  "ExtUtils::MakeMaker" => 0,
  "File::Copy" => 0,
  "File::Path" => 0,
  "IO::File" => 0,
  "JSON" => 0,
  "LWP::UserAgent" => 0,
  "MIME::Base32" => 0,
  "MIME::Base64" => 0,
  "Net::DNS::ZoneFile" => 0,
  "Net::IP" => 0,
  "NicTool" => 0,
  "Params::Validate" => "0.8",
  "RPC::XML" => 0,
  "RPC::XML::Parser" => 0,
  "SOAP::Lite" => "0.51",
  "Scalar::Util" => 0,
  "Test" => 0,
  "Test::More" => 0,
  "Test::Output" => 0,
  "Time::HiRes" => "1.9",
  "Time::Local" => 0,
  "Time::TAI64" => 2,
  "XML::Parser" => 0,
  "constant" => 0,
  "lib" => 0,
  "mod_perl" => 0,
  "parent" => "0.2",
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
