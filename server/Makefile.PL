use strict;
use warnings;

use ExtUtils::MakeMaker;

# Plain cpanm sends this to build.log; cpanm -v and perl Makefile.PL print it (#364).
unless ( eval { require DBD::mysql; DBD::mysql->VERSION('4.050'); 1 } ) {
    my $cfg = $ENV{DBD_MYSQL_CONFIG} || 'mysql_config';
    my ( $libs, $ver ) =
        map { my $o = `$cfg --$_ 2>/dev/null` // ''; chomp $o; $o } qw(libs version);
    my $client =
        !$libs                                    ? "not found: no $cfg on PATH"
      : $libs =~ /-lmariadb\b/                    ? "MariaDB Connector/C ($cfg --libs: $libs)"
      : ( $ver =~ /^(\d+)/ ? $1 : 0 ) < 8         ? "$ver, older than 8.0"
      :                                             '';
    warn <<"EOW" if $client;

**********************************************************************
DBD::mysql 4.050 or newer is not installed, and the client library here is
$client.

cpanm will pick DBD::mysql 5.x, which builds only against Oracle's
MySQL client library, 8.0 or newer. Here it will fail. Pick one:

  - the distro's DBD::mysql package, when it is 4.050 or newer
    (perl-DBD-MySQL on RHEL 9, libdbd-mysql-perl on Debian; RHEL 8's
    4.046 is too old)
  - an Oracle MySQL client dev package, 8.0 or newer, and let cpanm
    build 5.x (mysql-devel on RHEL: AppStream on 8, CRB on 9)
  - cpanm --notest DBD::mysql\@4.055: the 4.x line is still maintained
    and builds against MySQL and MariaDB
**********************************************************************

EOW
}

my %WriteMakefileArgs = (
    "ABSTRACT" => "NicTool API reference server",
    "AUTHOR"   => "Matt Simerson <msimerson\@cpan.org>, Damon Edwards, Abraham Ingersoll, Greg Schueler",
    "CONFIGURE_REQUIRES" => { "ExtUtils::MakeMaker" => 0 },
    "DISTNAME"           => "NicToolServer",
    "EXE_FILES"          => [],
    "LICENSE"            => "agpl_3",
    "MIN_PERL_VERSION"   => "5.030",
    "NAME"               => "NicToolServer",
    "PREREQ_PM"          => {
        "Apache::DBI"          => 0,
        "BIND::Conf_Parser"    => 0,
        "CGI"                  => "4.21",
        "Crypt::KeyDerivation" => 0,
        "Crypt::Mac::HMAC"     => 0,
        "CryptX"               => "0.021",
        "Cwd"                  => 0,
        "DBD::mysql"           => "4.050",
        "DBI"                  => "1.20",
        "DBIx::Simple"         => 0,
        "Data::Dumper"         => 0,
        "English"              => 0,
        "File::Copy"           => 0,
        "File::Path"           => 0,
        "HTML::Parser"         => 0,
        "IO::File"             => 0,
        "JSON"                 => 0,
        "LWP::UserAgent"       => 0,
        "MIME::Base32"         => 0,
        "MIME::Base64"         => 0,
        "Net::DNS::ZoneFile"   => 0,
        "Net::IP"              => 0,
        "Params::Validate"     => "0.8",
        "RPC::XML"             => 0,
        "RPC::XML::Parser"     => 0,
        "SOAP::Lite"           => "0.51",
        "Scalar::Util"         => 0,
        "Time::HiRes"          => "1.9",
        "Time::Local"          => 0,
        "Time::TAI64"          => 2,
        "XML::Parser"          => 0,
        "constant"             => 0,
        "lib"                  => 0,
        "parent"               => "0.2",
        "strict"               => 0,
        "vars"                 => 0,
        "warnings"             => 0
    },
    "TEST_REQUIRES" => {
        "Exporter"     => 0,
        "Test"         => 0,
        "Test::More"   => 0,
        "Test::Output" => 0
    },
    "VERSION" => "2.42",
    "test"    => { "TESTS" => "t/*.t" }
);

my %FallbackPrereqs = (
    "APR::Table"           => 0,
    "Apache::DBI"          => 0,
    "BIND::Conf_Parser"    => 0,
    "CGI"                  => 3,
    "Crypt::KeyDerivation" => 0,
    "Crypt::Mac::HMAC"     => 0,
    "CryptX"               => "0.021",
    "Cwd"                  => 0,
    "DBD::mysql"           => "4.050",
    "DBI"                  => "1.20",
    "DBIx::Simple"         => 0,
    "Data::Dumper"         => 0,
    "English"              => 0,
    "Exporter"             => 0,
    "ExtUtils::MakeMaker"  => 0,
    "File::Copy"           => 0,
    "File::Path"           => 0,
    "IO::File"             => 0,
    "JSON"                 => 0,
    "LWP::UserAgent"       => 0,
    "MIME::Base32"         => 0,
    "MIME::Base64"         => 0,
    "Net::DNS::ZoneFile"   => 0,
    "Net::IP"              => 0,
    "NicTool"              => 0,
    "Params::Validate"     => "0.8",
    "RPC::XML"             => 0,
    "RPC::XML::Parser"     => 0,
    "SOAP::Lite"           => "0.51",
    "Scalar::Util"         => 0,
    "Test"                 => 0,
    "Test::More"           => 0,
    "Test::Output"         => 0,
    "Time::HiRes"          => "1.9",
    "Time::Local"          => 0,
    "Time::TAI64"          => 2,
    "XML::Parser"          => 0,
    "constant"             => 0,
    "lib"                  => 0,
    "mod_perl"             => 0,
    "parent"               => "0.2",
    "strict"               => 0,
    "vars"                 => 0,
    "warnings"             => 0
);

unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
    delete $WriteMakefileArgs{TEST_REQUIRES};
    delete $WriteMakefileArgs{BUILD_REQUIRES};
    $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
