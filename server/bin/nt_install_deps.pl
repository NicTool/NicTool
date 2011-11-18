#!/usr/bin/env perl

# by Matt Simerson & Phil Nadeau
# circa 2008, but based in installer in Mail::Toaster dating back to the 20th century

use strict;
use warnings;

use CPAN;
use English qw( -no_match_vars );

my $deps = {
    'modules' => [
        { module => 'LWP'          , info => { port => 'p5-libwww' }, },
        { module => 'RPC::XML'     , info => { }, },
        { module => 'SOAP::Lite'   , info => { }, },
        { module => 'Apache2::SOAP', info => { }, },
        { module => 'DBI'          , info => { }, },
        { module => 'DBD::mysql'   , info => { }, },
        { module => 'DBIx::Simple' , info => { }, },
        { module => 'Apache::DBI'  , info => { }, },
        { module => 'Net::IP'      , info => { }, },
        { module => 'Digest::MD5'  , info => { }, },
        { module => 'Digest::HMAC' , info => { }, },
    ],
    'apps' => [
        { app => 'expat'         , info => { port => 'expat2',         dport=>'expat2' }, },
        { app => 'gettext'       , info => {}, },
        { app => 'gmake'         , info => { yum => 'make'  }, },
        { app => 'mysql-server-5', info => { port => 'mysql50-server', dport=>'mysql5',  yum => 'mysql-server' }, },
        { app => 'apache22'      , info => { dport=>'', yum => 'httpd' }, },
        { app => 'mod_perl2'     , info => { dport=>'', yum => 'mod_perl' }, },
        { app => 'rsync'         , info => { }, },
    ],
};

$EUID == 0 or die( "You will have better luck if you run me as root.\n");

# this causes problems when CPAN is not configured.
#$ENV{PERL_MM_USE_DEFAULT} = 1;       # supress CPAN prompts

$ENV{FTP_PASSIVE} = 1;        # for FTP behind NAT/firewalls

my @failed  = ();
foreach ( @{ $deps->{modules}  } ) {
    my $module = $_->{module} or die 'missing module name';
    my $info   = $_->{info};
    my $version = $info->{version} || '';
    print "checking for $module $version\n";
    eval "use $module $version";
    if ($EVAL_ERROR) {
        next if $info->{ships_with} && $info->{ships_with} eq 'perl';
        install_module( $module, $info, $version );
        eval "use $module $version";
        if ($EVAL_ERROR) {
            push @failed, $module;
        }
    }
}

if ( scalar @failed > 0 ) {
    print "The following modules failed installation:\n";
    print join( "\n", @failed );
    print "\n";
}

exit;

sub install_app_darwin {

    my $dport = '/opt/local/bin/port';
    if ( ! -x $dport ) {
        warn "could not find $dport. Is DarwinPort/MacPorts installed?\n";
        return;
    }

    foreach my $module ( @{ $deps->{apps} } ) {
        my $port = $module->{dport} || $module->{port};
        system "$dport install $port";
    };
};

sub install_app_freebsd {
    my $app = shift;
    my $portdir = shift || $app;

    my $checkcmd = "/usr/sbin/pkg_info | /usr/bin/grep $app";
    if (`$checkcmd`) {
        print "$app is installed.\n";
        next;
    }

    if ( ! chdir "/usr/ports/*/$portdir" ) {
        print "oops, couldn't chdir to /usr/ports/*/$portdir\n";
        return;
    };

    print "installing $app\n";
    system "make install clean";
}

sub install_module {

    my ($module, $info, $version) = @_;

    if ( lc($OSNAME) eq 'darwin' ) {
        install_module_darwin($module, $info, $version);
    }
    elsif ( lc($OSNAME) eq 'freebsd' ) {
        install_module_freebsd($module, $info, $version);
    }
    elsif ( lc($OSNAME) eq 'linux' ) {
        install_module_linux( $module, $info, $version);
    };

    eval "require $module";
    return 1 if ! $EVAL_ERROR;

    install_module_cpan($module, $version);
};

sub install_module_cpan {

    my ($module, $version) = @_;

    print " from CPAN...";

    # some Linux distros break CPAN by auto/preconfiguring it with no URL mirrors.
    # this works around that annoying little habit
    no warnings;
    $CPAN::Config = get_cpan_config();
    use warnings;

    if ( $module eq 'Provision::Unix' && $version ) {
        $module =~ s/\:\:/\-/g;
        $module = "M/MS/MSIMERSON/$module-$version.tar.gz";
    }
    CPAN::Shell->install($module);
    #CPAN::install $module;
}

sub install_module_darwin {
    my ($module, $info, $version) = @_;

    my $dport = '/opt/local/bin/port';
    if ( ! -x $dport ) {
        print "Darwin ports is not installed!\n";
        return;
    };

    my $port = "p5-$module";
    $port =~ s/::/-/g;
    system "sudo $dport install $port" 
        or warn "install failed for Darwin port $module";
}

sub install_module_freebsd {
    my ($module, $info, $version) = @_;

    print " from ports...";
    my $name = $info->{port} || $module;
    my $portname = "p5-$name";
    $portname =~ s/::/-/g;

    if (`/usr/sbin/pkg_info | /usr/bin/grep $portname`) {
        return print "$module is installed.\n";
    }

    print "installing $module";

    my ($portdir) = </usr/ports/*/$portname>;

    if ( $portdir && -d $portdir && chdir $portdir ) {
        print " from ports ($portdir)\n";
        system "make install clean" 
            and warn "'make install clean' failed for port $module\n";
    }
}

sub install_module_linux {
    my ($module, $info, $version) = @_;
    my $rpm = $info->{rpm};
    if ( $rpm ) {
        my $portname = "perl-$rpm";
        $portname =~ s/::/-/g;
        my $yum = '/usr/bin/yum';
        system "$yum -y install $portname" if -x $yum;
    }
};

sub get_cpan_config {

    my $ftp = `which ftp`; chomp $ftp;
    my $gzip = `which gzip`; chomp $gzip;
    my $unzip = `which unzip`; chomp $unzip;
    my $tar  = `which tar`; chomp $tar;
    my $make = `which make`; chomp $make;
    my $wget = `which wget`; chomp $wget;

    return 
{
  'build_cache' => q[10],
  'build_dir' => qq[$ENV{HOME}/.cpan/build],
  'cache_metadata' => q[1],
  'cpan_home' => qq[$ENV{HOME}/.cpan],
  'ftp' => $ftp,
  'ftp_proxy' => q[],
  'getcwd' => q[cwd],
  'gpg' => q[],
  'gzip' => $gzip,
  'histfile' => qq[$ENV{HOME}/.cpan/histfile],
  'histsize' => q[100],
  'http_proxy' => q[],
  'inactivity_timeout' => q[5],
  'index_expire' => q[1],
  'inhibit_startup_message' => q[1],
  'keep_source_where' => qq[$ENV{HOME}/.cpan/sources],
  'lynx' => q[],
  'make' => $make,
  'make_arg' => q[],
  'make_install_arg' => q[],
  'makepl_arg' => q[],
  'ncftp' => q[],
  'ncftpget' => q[],
  'no_proxy' => q[],
  'pager' => q[less],
  'prerequisites_policy' => q[follow],
  'scan_cache' => q[atstart],
  'shell' => q[/bin/csh],
  'tar' => $tar,
  'term_is_latin' => q[1],
  'unzip' => $unzip,
  'urllist' => [ 'http://www.perl.com/CPAN/', 'http://mirrors.kernel.org/pub/CPAN/', 'ftp://cpan.cs.utah.edu/pub/CPAN/', 'ftp://mirrors.kernel.org/pub/CPAN', 'ftp://osl.uoregon.edu/CPAN/', 'http://cpan.yahoo.com/', 'ftp://ftp.funet.fi/pub/languages/perl/CPAN/' ],
  'wget' => $wget, };
}


