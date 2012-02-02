package NicToolServer::Export;
# ABSTRACT: export DNS data to authoritative DNS servers

use strict;
use warnings;

use Cwd;
use DBIx::Simple;
use File::Path;
use Params::Validate qw/ :all /;

use lib 'lib';
use NicToolServer::Export::tinydns;
use NicToolServer::Export::BIND;

# this class and subclasses support nt_export.pl
# subclasses (see tinydns & BIND ^^) have server specific export logic

sub new {
    my $class = shift;
    my %p     = validate(
        @_,
        {   ns_id => { type => SCALAR },
            debug => { type => BOOLEAN, optional => 1 },
            force => { type => BOOLEAN, optional => 1 },
        }
    );

    return bless {
        ns_id  => $p{ns_id},           # current nameserver ID
        force  => $p{force},
        dbix_r => undef,
        dbix_w => undef,
        debug  => defined $p{debug} ? $p{debug} : 0,
        export_class => undef,
        export_dir => undef,
        export_format => 'tinydns',
        export_required => 1,
        export_serials => undef,       # export serials for this nsid?
        log_id         => undef,       # current log ID
        active_ns_ids  => undef,       # nsids for a zone
        ns_ref => undef,
        time_start => time,
        dir_orig => Cwd::getcwd,
        },
        $class;
}

sub daemon {
    my $self = shift;
    $self->export();
    my $end = time;
    my $waitleft = 60;
    if ( defined $self->{ns_ref}{export_interval} ) {
        $waitleft = $self->{ns_ref}{export_interval} - ( $end - $self->{time_start} );
    };
    if ( $waitleft > 0 ) {
        print ", sleeping $waitleft seconds\n";
        sleep $waitleft;
    };
};

sub elog {
    my $self    = shift;
    my $message = shift;
    my %p       = validate(
        @_,
        {   success => { type => BOOLEAN, optional => 1 },
            partial => { type => BOOLEAN, optional => 1 },
        }
    );
    my $logid = $self->get_log_id();
    my $sql = "UPDATE nt_nameserver_export_log 
    SET message=CONCAT_WS(', ',message,?)";

    my @args = $message;
    foreach (qw/ success partial /) {
        if ( defined $p{$_} ) {
            $sql .= ",$_=?";
            push @args, $p{$_};
        }
    }

    push @args, $self->{ns_id}, $logid;
    $sql .= "WHERE nt_nameserver_id=? AND nt_nameserver_export_log_id=?";
    $self->exec_query( $sql, \@args );
    print ", $message";
    return $message;
}

sub set_copied {
    my $self   = shift;
    my $copied = shift;
    $self->exec_query( 
        "UPDATE nt_nameserver_export_log SET copied=? WHERE nt_nameserver_id=?
            AND nt_nameserver_export_log_id=?",
        [ $copied, $self->{ns_id}, $self->{log_id} ] 
    );
}

sub set_partial {
    my $self   = shift;
    my $boolean = shift;
    $self->exec_query( 
        "UPDATE nt_nameserver_export_log SET partial=? 
        WHERE nt_nameserver_id=? AND nt_nameserver_export_log_id=?",
        [ $boolean, $self->{ns_id}, $self->{log_id} ] 
    );
}

sub set_status {
    my $self    = shift;
    my $message = shift;
    $self->exec_query( 
        "UPDATE nt_nameserver SET export_status=?  WHERE nt_nameserver_id=?",
         [ $message, $self->{ns_id} ] 
    );
}

sub cleanup_db {
    my $self = shift;

# delete the "started, 0 changed zones, exiting" log entries older than today
    $self->exec_query(
        "DELETE FROM nt_nameserver_export_log 
          WHERE copied=0 AND success=1
            AND date_start < DATE_SUB( CURRENT_TIMESTAMP, INTERVAL 1 DAY)
            AND nt_nameserver_id=?",
        [ $self->{ns_id} ]
    );
};

sub exec_query {
    my $self = shift;
    my ( $sql, $params, $extra ) = @_;

    my @caller = caller;
    my $err
        = sprintf( "exec_query called by %s, %s\n", $caller[0], $caller[2] );
    $err .= "\t$sql\n\t";

    die "invalid arguments to exec_query!" if $extra;

    my @params;
    if ( defined $params ) {    # dereference $params into @params
        @params = ref $params eq 'ARRAY' ? @$params : $params;
        $err .= join( ', ', @params ) . "\n";
    }

    warn $err if $self->{debug};
    my $dbix_r = $self->{dbix_r};
    my $dbix_w = $self->{dbix_w};

    if ( $sql =~ /^INSERT INTO/ ) {
        my ($table) = $sql =~ /INSERT INTO (\w+)[\s\(]/;
        eval { $dbix_w->query( $sql, @params ); };
        if ( $@ or $dbix_w->error ne 'DBI error: ' ) {
            warn $err . $dbix_w->error if $self->{debug};
            return;
        }
        return $dbix_w->last_insert_id( undef, undef, $table, undef );

        # don't test the value of last_insert_id. If the table doesn't have an
        # autoincrement field, the value is always zero
    }
    elsif ( $sql =~ /^DELETE|UPDATE/ ) {
        eval { $dbix_w->query( $sql, @params ) };
        if ( $@ or $dbix_w->error ne 'DBI error: ' ) {
            warn $err . $dbix_w->error if $self->{debug};
            return;
        }
        return $dbix_w->query("SELECT ROW_COUNT()")->list;
    }

    my $r;
    eval { $r = $dbix_r->query( $sql, @params )->hashes; };
    warn "$err\t$@" if $@;    #&& $self->{debug} );
    return $r;
}

sub export {
    my $self = shift;

    $self->preflight or return;
    $self->get_active_nameservers;

    my $last_ts = 'never';
    if ( $self->{force} ) {
        $self->elog("forced");
    }
    elsif ( ! $self->{export_required} ) {
        my $last_copy;
        if ( $self->{export_format} eq 'tinydns' ) {
            $last_copy = $self->get_last_ns_export(success=>1,copied=>1);
        }
        else {
            $self->get_last_ns_export(success=>1);
        }
        if ( $last_copy->{date_end} ) {
            $last_ts = substr( $last_copy->{date_end}, 5, 11 );
        };
        my $now_ts = substr( localtime( time ), 4, 15 );
        $self->set_status("no changes:$now_ts last:$last_ts");
        $self->elog("exiting",success=>1);
        return 1;
    };

    my $before = time;
    $self->set_status("exporting from DB");
    $self->{export_class}->export_db();
    my $elapsed = '';
    if ( (time - $before) > 5 ) { $elapsed = ' ('. (time - $before) . ' secs)' };
    $self->elog('exported'.$elapsed);

    $self->postflight or return;
    return 1;
}

sub get_dbh {
    my $self = shift;
    my %p    = validate(
        @_,
        {   dsn    => { type => SCALAR },
            user   => { type => SCALAR },
            pass   => { type => SCALAR },
            dsn_w  => { type => SCALAR, optional => 1 },
            user_w => { type => SCALAR, optional => 1 },
            pass_w => { type => SCALAR, optional => 1 },
        }
    );

   # get database handles (r/w and r/o)
   #
   # the read handle is the default handle. If a second write DSN is provided,
   # it is used for INSERT/UPDATE/DELETE queries. This is useful for sites
   # with one-way replicated database servers with a local db slave.

    die "invalid DSN! ($p{dsn})" if $p{dsn} !~ /^DBI/;

    $self->{dbix_r} = DBIx::Simple->connect( $p{dsn}, $p{user}, $p{pass} )
        or die DBIx::Simple->error;

    $self->{dbix_w} = DBIx::Simple->connect(
        $p{dsn_w}  || $p{dsn},
        $p{user_w} || $p{user},
        $p{pass_w} || $p{pass}
    ) or die DBIx::Simple->error;
    return $self->{dbix_r};
}

sub get_export_dir {
    my $self = shift;

    return $self->{export_dir} if $self->{export_dir};

    $self->get_active_nameservers();  # populate $self->{ns_ref}

    my $dir;

    if ( defined $self->{ns_ref}{datadir} ) {

        # try the directory defined in nt_nameserver.datadir
        $dir = $self->{ns_ref}{datadir};
        if ( $dir && -d $dir ) {
            if ( -w $dir && ( ! -e "$dir/data" || -w "$dir/data" ) ) {
                $self->{export_dir} = $dir;
                #$self->elog("using $dir");
                return $dir;
            };
            $self->elog("export dir ($dir) not writable");
        };

        # try the local working directory
        $dir = getcwd . '/data-' . $self->{ns_ref}{name};
        $dir =~ s/\.$//;   # strip off any trailing dot
        if ( -d $dir ) {
            if ( -w $dir ) {
                #$self->elog("using $dir");
                $self->{export_dir} = $dir;
                return $dir;
            };
            $self->elog("export dir ($dir) not writable");
            return;
        }
    }
    else {
        $dir = getcwd . '/data-all';  # special nsid = 0 (all) specified
        if ( -d $dir ) {
            $self->{export_dir} = $dir;
            return $dir;
        };
    };

    eval { mkpath( $dir, { mode => 0755 } ); };
    if ( -d $dir ) {     # mkpath just created it
        $self->elog("created $dir");
        $self->{export_dir} = $dir;
        return $dir;     # I have write permission
    };
    $self->elog("unable to create dir ($dir): $@");
    return;
};

sub get_last_ns_export {
    my $self = shift;
    my %p    = validate(
        @_,
        {   success => { type => BOOLEAN, optional => 1 },
            partial => { type => BOOLEAN, optional => 1 },
            copied  => { type => BOOLEAN, optional => 1 },
        }
    );

    my $sql = "SELECT nt_nameserver_export_log_id AS id, 
        date_start, date_end, message
      FROM nt_nameserver_export_log
        WHERE nt_nameserver_id=?";

    my @args = $self->{ns_id};
    foreach my $f (qw/ success partial copied /) {
        if ( defined $p{$f} ) {
            $sql .= " AND $f=?";
            push @args, $p{$f};
        }
    }

    $sql .= " ORDER BY date_start DESC LIMIT 1";

    my $logs = $self->exec_query( $sql, \@args );
    if ( scalar @$logs == 0 ) {
        my $message = "no previous export";
        $message = "no previous successful export" if defined $p{success} && $p{success} == 1;
        $self->elog( $message );
        return;
    };
    return $logs->[0];
}

sub get_ns_id {
    my $self = shift;
    my %p    = validate(
        @_,
        {   id   => { type => SCALAR, optional => 1 },
            name => { type => SCALAR, optional => 1 },
            ip   => { type => SCALAR, optional => 1 },
        }
    );

    die "An id, ip, or name must be passed to get_ns_id\n"
        if ( !$p{id} && !$p{name} && !$p{id} );

    my @args;
    my $sql = "SELECT nt_nameserver_id AS id FROM nt_nameserver 
        WHERE deleted=0";

    if ( defined $p{id} ) {
        $sql .= " AND nt_nameserver_id=?";
        push @args, $p{id};
    }
    if ( defined $p{ip} ) {
        $sql .= " AND address=?";
        push @args, $p{ip};
    }
    if ( defined $p{name} ) {
        $sql .= " AND name=?";
        push @args, $p{name};
    }

    my $nameservers = $self->exec_query( $sql, \@args );
    return $nameservers->[0]->{id};
}

sub get_ns_zones {
    my $self = shift;
    my %p = validate( @_,
        { last_modified => { type => SCALAR, optional => 1 },
          query_result  => { type => BOOLEAN, optional => 1 }, 
        },
    );

    my $sql = "SELECT z.nt_zone_id, z.zone, z.mailaddr, z.serial, z.refresh,
        z.retry, z.expire, z.minimum, z.ttl, z.location, z.last_modified,
 (SELECT GROUP_CONCAT(nt_nameserver_id) FROM nt_zone_nameserver n 
    WHERE n.nt_zone_id=z.nt_zone_id) AS nsids
     FROM nt_zone z";

    my @args;
    if ( $self->{ns_id} == 0 ) {
        $sql .= " WHERE z.deleted=0";  # all zones, regardless of NS pref
    }
    else {
        $sql .= "
  LEFT JOIN nt_zone_nameserver n ON z.nt_zone_id=n.nt_zone_id
    WHERE n.nt_nameserver_id=? AND z.deleted=0";
        push @args, $self->{ns_id};
    }

    if ( $p{last_modified} ) {
        $sql .= " AND z.last_modified > ?";
        push @args, $p{last_modified};
    }

    return ($sql,@args) if $p{query_result};
    my $r = $self->exec_query( $sql, \@args ) or return [];
    $self->elog( "retrieved " . scalar @$r . " zones" );
    return $r;
}

sub get_ns_records {
    my $self = shift;
    my %p = validate( @_,
        { last_modified => { type => SCALAR, optional => 1 },
          query_result  => { type => BOOLEAN, optional => 1 }, 
        },
    );

    my $sql = "SELECT r.name, r.ttl, t.name AS type, r.address, r.weight, 
        r.priority, r.other, r.location, z.zone AS zone_name,
        UNIX_TIMESTAMP(timestamp) AS timestamp
      FROM nt_zone_record r
        LEFT JOIN resource_record_type t ON t.id=r.type_id
        LEFT JOIN nt_zone_nameserver ns ON ns.nt_zone_id=r.nt_zone_id
        JOIN nt_zone z ON ns.nt_zone_id=z.nt_zone_id
      WHERE z.deleted=0
        AND r.deleted=0";

    my @args;
    if ( $self->{ns_id} != 0 ) {
        $sql .= " AND ns.nt_nameserver_id=?";
        push @args, $self->{ns_id};
    }

    if ( $p{last_modified} ) {
        $sql .= " AND z.last_modified > ?";
        push @args, $p{last_modified};
    }

    return ($sql,@args) if $p{query_result};
    my $r = $self->exec_query( $sql, \@args ) or return [];
    $self->elog( "retrieved " . scalar @$r . " records" );
    return $r;
}

sub get_log_id {
    my $self = shift;
    my %p    = validate(
        @_,
        {   success => { type => BOOLEAN, optional => 1 },
            partial => { type => BOOLEAN, optional => 1 },
            copied  => { type => BOOLEAN, optional => 1 },
        }
    );
    return $self->{log_id} if defined $self->{log_id};
    my $message = "started";
    my $sql   = "INSERT INTO nt_nameserver_export_log 
        SET nt_nameserver_id=?, date_start=CURRENT_TIMESTAMP(), message=?";

    my @args = ( $self->{ns_id}, $message );
    foreach (qw/ success partial copied /) {
        if ( defined $p{$_} ) {
            $sql .= ",$_=?";
            push @args, $p{$_};
        }
    }

    $self->{log_id} = $self->exec_query( $sql, \@args );
    return $self->{log_id};
}

sub get_modified_zones {
    my $self = shift;
    my %p = validate( @_, { since => { type => SCALAR | UNDEF, optional => 1 }, } );

    my $sql = "SELECT COUNT(*) AS count FROM nt_zone z WHERE 1=1";
    my @args;

    if ( defined $self->{ns_id} && $self->{ns_id} != 0 ) {
        $sql = "SELECT COUNT(*) AS count FROM nt_zone_nameserver zn
        LEFT JOIN nt_zone z ON zn.nt_zone_id=z.nt_zone_id
        WHERE zn.nt_nameserver_id=?";
        @args = $self->{ns_id};
    };

    if ( defined $p{since} ) {
        $sql .= " AND z.last_modified>?";
        push @args, $p{since};
    };

    my $r = $self->exec_query( $sql, \@args );
    return $r->[0]{count};
}

sub get_zone_ns_ids {
    my $self = shift;
    my $zone = shift or die "missing zone";
    ref $zone or die "invalid zone object";

    return $self->{dbix_r}->query(
        "SELECT zn.nt_nameserver_id 
          FROM nt_zone_nameserver zn
            LEFT JOIN nt_nameserver n ON zn.nt_nameserver_id=n.nt_nameserver_id
                WHERE zn.nt_zone_id=? AND n.deleted=0",
        $zone->{nt_zone_id}
    )->flat;
}

sub get_active_nameservers {
    my $self = shift;
    return $self->{active_ns} if defined $self->{active_ns};

    my $sql = "SELECT * FROM nt_nameserver WHERE deleted=0 
        ORDER BY nt_nameserver_id";
    $self->{active_ns} = $self->exec_query($sql);    # populated

    foreach my $r ( @{ $self->{active_ns} } ) {
        $self->{active_ns_ids}{ $r->{nt_nameserver_id} } = $r;

        # tinydns can autogenerate serial numbers based on data file
        # timestamp. Export serials for everyone else.
        $r->{export_serials}++ if $r->{export_format} ne 'tinydns';
    }

    my $export_format;
    if ( $self->{ns_id} ) {
        $self->{ns_ref} = $self->{active_ns_ids}{$self->{ns_id}};
        $self->{export_format} = $self->{ns_ref}{export_format};
    }
    else {
        my $first = $self->{active_ns_ids}{ $self->{active_ns}[0] };
        $self->{export_format} = $first->{export_format} if $first->{export_format};
    };

    if ( $self->{export_format} eq 'bind' ) {
        $self->{export_class} = NicToolServer::Export::BIND->new( $self );
    }
    elsif ( $self->{export_format} eq 'tinydns' ) {
        $self->{export_class} = NicToolServer::Export::tinydns->new( $self );
    }
    elsif ( $self->{export_format} eq 'powerdns' ) {
        $self->{export_class} = NicToolServer::Export::PowerDNS->new( $self );
    }
    elsif ( $self->{export_format} eq 'maradns' ) {
        $self->{export_class} = NicToolServer::Export::Maradns->new( $self );
    }
    else {
        die "unknown export format: $self->{export_format}\n";
    };
    return $self->{active_ns};
}

sub preflight {
    my $self = shift;

    return 1 if $self->{export_required} == 0; # already called

    $self->get_log_id;

    # bail out if no export required
    #    get timestamp of last successful export
    my $export = $self->get_last_ns_export( success => 1 );
    if ( $export ) {
        my $ts_success = $export->{date_start};
        if ( $ts_success ) {
# do any zones for this NS have changes since the last successful export?
            my $c = $self->get_modified_zones( since => $ts_success );
            if ( $c == 0 ) {
                $self->{export_required} = 0;
                $self->elog("No changed zones");
            }
            else {
                $self->elog("$c changed zones");
            };
        };
    };
    $self->elog("export required") if $self->{export_required};

    # determine export directory
    $self->get_export_dir or return;
    $self->write_runfile();

    return 1;
}

sub postflight {
    my $self = shift;

    $self->{export_class}->postflight or return;

    $self->update_status();

    $self->cleanup_db();

    # mark export successful
    $self->elog("complete", success=>1);
}

sub update_status {
    my $self = shift;
    my $run_time = time - $self->{time_start};
    my $interval = $self->{ns_ref}{export_interval} || 60;
    my $waitleft = $interval - $run_time;
    if ( $run_time < $interval ) {
        my $tstring = localtime( $self->{time_start} + $run_time + $waitleft );
        $tstring = substr( $tstring, 4, 15 );
        $self->set_status( "last:SUCCESS, next:$tstring" );
    }
    else {
        $self->set_status( "last: SUCCESS" );
    };
};

sub write_runfile {
    my $self = shift;

    chdir $self->{dir_orig};
    return if -f 'run';
    open my $F, '>', 'run' or return;
    print $F <<EORUN
#!/bin/sh
#
# direct STDERR to STDOUT
exec 2>&1
#
# if run file is started by something like init, upstart, or daemontools,
# setuidgid to the 'nictool' user, and run the export, logging to syslog.
#exec setuidgid nictool ./nt_export.pl -nsid $self->{ns_id} -daemon | logger
#
# For cron, at, or other periodic trigger
#exec setuidgid nictool ./nt_export.pl -nsid $self->{ns_id} | logger
#
# For interactive use by a human. If said human is logged in as the
# 'nictool' user, this works well. Otherwise, you may have to alter
# ownership of the files created. The -force option is included because
# odds are, if you are running this by hand, you want the export to complete
# regardless of any DB changes.
exec setuidgid nictool ./nt_export.pl -nsid $self->{ns_id} -force
EORUN
;
    close $F;
    CORE::chmod( oct('0755'), 'run' );
};

sub zr_soa {
    my $self = shift;
    my $z  = shift;

    my @ns_ids       = split(',', $z->{nsids} );
    $z->{timestamp}  = '';       # does it make sense to?
    $z->{location} ||= '';
    $z->{nsname}     = $self->{active_ns_ids}{ $ns_ids[0] }{name};
    $z->{serial}     = $self->{ns_ref}{export_serials} ? $z->{serial} : '',

    my $r = $self->{export_class}->zr_soa( $z );
    return $r;
}

sub zr_ns { 
    my $self = shift;
    my $z = shift;
    my $r;
    foreach my $nsid ( split(',', $z->{nsids} ) ) {
        my $ns_ref = $self->{active_ns_ids}{$nsid};
        $r .= $self->{export_class}->zr_ns(
            {
                name     => $z->{zone},
                address  => $self->qualify( $ns_ref->{name}, $z->{zone} ),
                ttl      => $ns_ref->{ttl},
                location => $self->{ns_ref}{location} || '',
                timestamp => '',
            },
        );
    }
    return $r;
}

sub is_ip_port {
    my ( $self, $port ) = @_;

    return $port if ( $port >= 0 && $port <= 65535 );
    warn "value not within IP port range: 0 - 65535";
    return 0;
}

sub qualify {
    my ( $self, $record, $zone ) = @_;
    return $record if substr($record,-1,1) eq '.';  # record ends in .
    $zone ||= $self->{zone_name} or return $record;

# substr is measurably faster than a regexp
    return $record if $zone eq substr($record,(-1*length($zone)),length($zone));
    return "$record.$zone"                 # append missing zone name
}


1;

__END__


