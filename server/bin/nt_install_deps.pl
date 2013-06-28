#!/usr/bin/perl

# v1.7 - 2013-04-20  - Matt
#      - get list of modules from Makefile.PL or dist.ini
#      - abstracted yum and apt into subs
#
# v1.6 - 2013-04-01  - Matt
#      - improved error reporting for FreeBSD port installs
#
# v1.5 - 2013-03-27  - Matt
#      - added option to specify port category
#
# v1.4 - 2012-10-23  - Matt
#      - improved yum & apt-get module installer
#
# v1.3 - 2012-10-23  - Matt
#      - added apt-get support
#      - added app install support
#
# circa 2008, by Matt Simerson & Phil Nadeau
#      - based on installer in Mail::Toaster dating back to the 20th century

use strict;
use warnings;

use CPAN;
use English qw( -no_match_vars );

my $apps = [
    { app => 'expat'         , info => { port => 'expat2',         dport=>'expat2' }, },
    { app => 'gettext'       , info => {}, },
    { app => 'gmake'         , info => { yum => 'make', apt => 'make' }, },
    { app => 'mysql-server-5', info => { port => 'mysql50-server', dport=>'mysql5',
                                         yum  => 'mysql-server',   apt => 'mysql-server' }, },
    { app => 'apache22'      , info => { dport=>'', yum => 'httpd', apt=>'apache2' }, },
    { app => 'mod_perl2'     , info => { dport=>'', yum => 'mod_perl', apt=>'libapache2-mod-perl2' }, },
    { app => 'rsync'         , info => { }, },
];

$EUID == 0 or die "You will have better luck if you run me as root.\n";

my @failed;
foreach ( @$apps ) {
    my $name = $_->{app} or die 'missing app name';
    install_app( $name, $_->{info} );
};

foreach ( get_perl_modules() ) {
#print Dumper($_);
    my $module = $_->{module} or die 'missing module name';
    my $info   = $_->{info};
    my $version = $info->{version} || '';
    print "checking for $module $version\n";

## no critic
    eval "use $module $version";
    next if ! $EVAL_ERROR;
    next if $info->{ships_with} && $info->{ships_with} eq 'perl';

    install_module( $module, $info, $version );
    eval "use $module $version";
## use critic
    if ($EVAL_ERROR) {
        push @failed, $module;
    }
}

if ( scalar @failed > 0 ) {
    print "The following modules failed installation:\n";
    print join( "\n", @failed );
    print "\n";
}

exit;

sub get_perl_modules {
    if ( -f 'dist.ini' ) {
        return get_perl_modules_from_ini();
    };
    if ( -f 'Makefile.PL' ) {
        return get_perl_modules_from_Makefile_PL();
    };
    die "unable to find module list. Run this script in the dist dir\n";
};

sub get_perl_modules_from_Makefile_PL {
    my $fh = new IO::File 'Makefile.PL', 'r'
        or die "unable to read Makefile.PL\n";

    my $in = 0;
    my @modules;
    foreach my $line ( <$fh> ) {
        if ( $line =~ /PREREQ_PM/ ) {
            $in++;
            next;
        };
        next if ! $in;
        last if $line =~ /}/;
        next if $line !~ /=/;  # no = char means not a module
        my ($mod,$ver) = split /\s*=\s*/, $line;
        $mod =~ s/[\s'"\#]*//g;   # remove whitespace and quotes
        next if ! $mod;
        push @modules, name_overrides($mod);
#print "module: .$mod.\n";
    }
    $fh->close;
    return @modules;
};

sub get_perl_modules_from_ini {
    my $fh = new IO::File 'dist.ini', 'r'
        or die "unable to read dist.ini\n";

    my $in = 0;
    my @modules;
    foreach my $line ( <$fh> ) {
        if ( '[Prereqs]' eq substr($line,0,9) ) {
            $in++;
            next;
        };
        next if ! $in;
#       print "line: $line\n";
        next if ';' eq substr($line,0,1); # comment
        last if '[' eq substr($line,0,1); # [...] starts a new section
        my ($mod,$ver) = split /\s*=\s*/, $line;
        $mod =~ s/\s*//g;                 # remove whitespace
        next if ! $mod || ! defined $ver;
        push @modules, name_overrides($mod);
#       print "module: $mod\n";
    }
    $fh->close;
#print Dumper(\@modules);
    return @modules;
};

sub install_app {
    my ( $app, $info) = @_;

    if ( lc($OSNAME) eq 'darwin' ) {
        install_app_darwin($app, $info );
    }
    elsif ( lc($OSNAME) eq 'freebsd' ) {
        install_app_freebsd($app, $info );
    }
    elsif ( lc($OSNAME) eq 'linux' ) {
        install_app_linux( $app, $info );
    };

};

sub install_app_darwin {
    my ($app, $info ) = @_;

    my $port = $info->{dport} || $info->{port} || $app;

    if ( ! -x '/opt/local/bin/port' ) {
        print "MacPorts is not installed! Consider installing it.\n";
        return;
    }

    system "/opt/local/bin/port install $port"
        and warn "install failed for Darwin port $port";
}

sub install_app_freebsd {
    my ($app, $info ) = @_;

    print " from ports...";
    my $name = $info->{port} || $app;

    if ( `/usr/sbin/pkg_info | /usr/bin/grep $name` ) {
        return print "$app is installed.\n";
    }
    elsif( `/usr/sbin/pkg info | /usr/bin/grep $name` ) {
        return print "$app is installed.\n";
    }

    print "installing $app";

    my $category = $info->{category} || '*';
    my ($portdir) = glob "/usr/ports/$category/$name";

    if ( $portdir && -d $portdir && chdir $portdir ) {
        print " from ports ($portdir)\n";
        system "make install clean"
            and warn "'make install clean' failed for port $app\n";
    };
};

sub install_app_linux {
    my ($app, $info ) = @_;

    if ( -x '/usr/bin/yum' ) {
        my $rpm = $info->{yum} || $app;
        system "/usr/bin/yum -y install $rpm";
    }
    elsif ( -x '/usr/bin/apt-get' ) {
        my $package = $info->{apt} || $app;
        system "/usr/bin/apt-get -y install $package";
    }
    else {
        warn "no Linux package manager detected\n";
    };
};


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

## no critic
    eval "require $module";
## use critic
    return 1 if ! $EVAL_ERROR;

    install_module_cpan($module, $version);
};

sub install_module_cpan {

    my ($module, $version) = @_;

    print " from CPAN...";
    sleep 1;

    # this causes problems when CPAN is not configured.
    #$ENV{PERL_MM_USE_DEFAULT} = 1;       # supress CPAN prompts

    $ENV{FTP_PASSIVE} = 1;        # for FTP behind NAT/firewalls

    # some Linux distros break CPAN by auto/preconfiguring it with no URL mirrors.
    # this works around that annoying little habit
    no warnings;
    $CPAN::Config = get_cpan_config();
    use warnings;

    # a hack to grab the latest version on CPAN before its hits the mirrors
    if ( $module eq 'Provision::Unix' && $version ) {
        $module =~ s/\:\:/\-/g;
        $module = "M/MS/MSIMERSON/$module-$version.tar.gz";
    }
    CPAN::Shell->install($module);
}

sub install_module_darwin {
    my ($module, $info, $version) = @_;

    my $dport = '/opt/local/bin/port';
    if ( ! -x $dport ) {
        print "MacPorts is not installed! Consider installing it.\n";
        return;
    }

    my $port = "p5-$module";
    $port =~ s/::/-/g;
    system "$dport install $port"
        and warn "install failed for Darwin port $module";
}

sub install_module_freebsd {
    my ($module, $info, $version) = @_;

    my $name = $info->{port} || $module;
    my $portname = "p5-$name";
    $portname =~ s/::/-/g;

    print " from ports...$portname...";

    if ( `/usr/sbin/pkg_info | /usr/bin/grep $portname` ) {
        return print "$module is installed.\n";
    }
    elsif( `/usr/sbin/pkg info | /usr/bin/grep $portname` ) {
        return print "$module is installed.\n";
    }

    print "installing $module ...";

    my $category = $info->{category} || '*';
    my ($portdir) = glob "/usr/ports/$category/$portname";

    if ( ! $portdir || ! -d $portdir ) {
        print "oops, no match at /usr/ports/$category/$portname\n";
        return;
    };

    if ( ! chdir $portdir ) {
        print "unable to cd to /usr/ports/$category/$portname\n";
    };

    print " from ports ($portdir)\n";
    system "make install clean"
        and warn "'make install clean' failed for port $module\n";
}

sub install_module_linux {
    my ($module, $info, $version) = @_;

    my $package;
    if ( -x '/usr/bin/yum' ) {
        return install_module_linux_yum($module, $info);
    }
    elsif ( -x '/usr/bin/apt-get' ) {
        return install_module_linux_apt($module, $info);
    }
    warn "no Linux package manager detected\n";
};

sub install_module_linux_yum {
    my ($module, $info) = @_;
    my $package;
    if ( $info->{yum} ) {
        $package = $info->{yum};
    }
    else {
        $package = "perl-$module";
        $package =~ s/::/-/g;
    };
    system "/usr/bin/yum -y install $package";
};

sub install_module_linux_apt {
    my ($module, $info) = @_;
    my $package;
    if ( $info->{apt} ) {
        $package = $info->{apt};
    }
    else {
        $package = 'lib' . $module . '-perl';
        $package =~ s/::/-/g;
    };
    system "/usr/bin/apt-get -y install $package";
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

sub name_overrides {
    my $mod = shift;
# Package and port managers have naming conventions for perl modules. The
# methods will typically work out the name based on the module name and a
# couple rules. When that doesn't work, add entries here for FreeBSD (port),
# MacPorts ($dport), yum, and apt.
    my @modules = (
        { module=>'LWP::UserAgent', info => { cat=>'www', port=>'p5-libwww', dport=>'p5-libwww-perl' }, },
        { module=>'Mail::Send'    , info => { port => 'Mail::Tools', }  },
    );
    my ($match) = grep { $_->{module} eq $mod } @modules;
    return $match if $match;
    return { module=>$mod, info => { } };
};

# PODNAME: install_deps.pl
# ABSTRACT: install dependencies with package manager or CPAN
