#!perl

use strict;
use warnings;

use CPAN;
use English;

my %required_apps = (
    'expat'             => { cat => 'textproc',  port => 'expat2',         dport=>'expat2' },
    'gettext'           => { cat => 'devel',     port => 'gettext',        dport=>'gettext'},
    'gmake'             => { cat => 'devel',     port => 'gmake',          dport=>'gmake'  },
    'mysql-server-5'    => { cat => 'databases', port => 'mysql50-server', dport=>'mysql5' },
    'apache22'          => { cat => 'www',       port => 'apache22',       dport=>'' },
    'mod_perl2'         => { cat => 'www',       port => 'mod_perl2',      dport=>'' },
);

my %required_modules = (
    'LWP'          => { cat => 'www',       port => 'p5-libwww'     },
    'RPC::XML'     => { cat => 'net',       port => 'p5-RPC-XML'    },
    'SOAP::Lite'   => { cat => 'net',       port => 'p5-SOAP-Lite'  },
    'Apache2::SOAP'=> { cat => 'net',       port => 'p5-Apache2-SOAP' },
    'DBI'          => { cat => 'databases', port => 'p5-DBI'        },
    'DBD::mysql'   => { cat => 'databases', port => 'p5-DBD-mysql'  },
    'Apache::DBI'  => { cat => 'www',       port => 'p5-Apache-DBI' },
    'Net::IP'      => { cat => 'net-mgmt',  port => 'p5-Net-IP'     },
    'Digest::MD5'  => { cat => 'security',  port => 'p5-Digest-MD5' },
);

my $sudo = $EFFECTIVE_USER_ID == 0 ? '' : 'sudo';

if ( lc($OSNAME) eq 'freebsd' ) {
    print "detected FreeBSD, installing dependencies from ports\n";
    install_freebsd_ports();    
}
elsif ( lc($OSNAME) eq 'darwin' ) {
    install_darwin_ports();    
}

print "installing dependencies with CPAN.\n";
install_cpan();

exit;


sub install_cpan {

    if ( $EFFECTIVE_USER_ID != 0 ) {
        warn "cannot use CPAN to install modules because you aren't root!\n";
        return;
    };

    foreach my $module ( keys %required_modules ) {
        CPAN::install $module;
    };
};

sub install_darwin_ports {

    my $dport = '/opt/local/bin/port';
    if ( ! -x $dport ) {
        warn "could not find $dport. Is DarwinPort/MacPorts installed?\n";
        return;
    }
    foreach my $module ( keys %required_modules ) {
        my $port = $required_modules{$module}->{'dport'} 
                || $required_modules{$module}->{'port'};
        system "$sudo $dport install $port";
    };
};

sub install_freebsd_ports {

    foreach my $app ( keys %required_apps ) {

        my $category = $required_apps{$app}->{'cat'};
        my $portdir  = $required_apps{$app}->{'port'};
        die "cat/port not set" if ( !$category || !$portdir );

        my $checkcmd = "/usr/sbin/pkg_info | /usr/bin/grep $app";
        if (`$checkcmd`) {
            print "$app is installed.\n";
            next;
        }

        print "installing $app\n";
        if ( chdir "/usr/ports/$category/$portdir" ) {
            ;
            system "make install clean";
        }
        else {
            print "oops, couldn't chdir to /usr/ports/$category/$portdir\n";
        }
    }

    foreach my $module ( keys %required_modules ) {

        my $category = $required_modules{$module}->{'cat'};
        my $portdir  = $required_modules{$module}->{'port'};

        if ( !$category || !$portdir ) {
            warn "incorrect hash key or values for $module\n";
            next "cat/port not set";
        };

        my ($registered_name) = $portdir =~ /^p5-(.*)$/;

        if ( `/usr/sbin/pkg_info | /usr/bin/grep $registered_name` ) {
            print "$module is installed.\n";
            next;
        }

        print "installing $module\n";
        if ( ! chdir "/usr/ports/$category/$portdir" ) {
            warn "error, couldn't chdir to /usr/ports/$category/$portdir\n";
            next;
        }
        system "$sudo make install clean";
    }
}
