package NicToolServer::Export::DynECT;
# ABSTRACT: export NicTool DNS data to DynECT managed DNS

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::Base';

use Carp;
use Data::Dumper;
use JSON;
use LWP::UserAgent;

my $dyn_rest_url = 'https://api.dynect.net/REST/';

my $ua = LWP::UserAgent->new;
   $ua->agent("NicTool/2.24");
#  $ua->ssl_opts(verify_hostname=>0);

my $json = JSON->new;

sub get_ns_zones {
    my $self = shift;

    my $sql = "SELECT z.nt_zone_id, z.zone, z.mailaddr, z.serial, z.refresh,
       z.retry, z.expire, z.minimum, z.ttl, z.location, z.last_modified,
       (SELECT GROUP_CONCAT(nt_nameserver_id) FROM nt_zone_nameserver n
        WHERE n.nt_zone_id=z.nt_zone_id) AS nsids
           FROM nt_zone z
        WHERE z.deleted=0";

    my $r = $self->{nte}->exec_query( $sql ) or return [];
    $self->{nte}->elog( "retrieved " . scalar @$r . " zones" );
    return $r;
}

sub export_db {
    my ($self) = @_;

    # for incremental, get_ns_zones returns only changed zones.
   #foreach my $z ( @{ $self->{nte}->get_ns_zones() } ) {
    foreach my $z ( @{ $self->get_ns_zones() } ) {
        my $zone = $z->{zone};
        push @{$self->{zone_list}}, $zone;
        $self->{nte}{zone_name} = $zone;
        if ($self->get_zone($zone)) { $self->delete_zone($zone); }
        #$self->add_zone($zone);  # upload does this

        my $zone_str;
        # these records don't exist in DB, generate them here
        $zone_str .= $self->{nte}->zr_soa( $z );
        # stupid Dyn API overrides these, manually add them later.
        #$zone_str .= $self->{nte}->zr_ns(  $z );

        my $records = $self->get_records( $z->{nt_zone_id} );
        foreach my $r ( @$records ) {
            my $method = 'zr_' . lc $r->{type};
            $r->{location}  ||= '';
            $zone_str .= $self->$method($r);
        }

        my $dynr = $self->get_api_response('POST', "ZoneFile/$zone/", {
                file => $zone_str,
                });
        print Dumper($dynr);
# TODO: poll the job until the import is completed

# manually add NS records
        foreach my $nsid ( split(',', $z->{nsids} ) ) {
            my $ns_ref = $self->{nte}{active_ns_ids}{$nsid};
            my $req = {
                name     => $z->{zone},
                address  => $self->qualify($ns_ref->{name}, $zone),
                ttl      => $ns_ref->{ttl},
            };
            my $r = $self->api_zr_ns( $req );
            print Dumper($req, $r);
        }

        $self->publish_zone($zone);
    }

    foreach my $z ( @{ $self->{nte}->get_ns_zones( deleted => 1) } ) {
        my $zone = $z->{zone};
        if ($self->delete_zone($zone)) {
            $self->{nte}->elog("deleted $zone");
            $self->{nte}{zones_deleted}{$zone} = 1;
        }
        else {
            $self->{nte}->elog("error deleting $zone");
        }
    };
    return 1;
}

sub add_zone_record {
    my ($self, $type, $zone, $fqdn, $req) = @_;

    # https://api.dynect.net/REST/ARecord/<zone>/<FQDN>/
    $type = uc($type) . 'Record';

    my $res = $self->get_api_response('POST', "$type/$zone/$fqdn", $req);
    if ($res->is_success) {
        my $api_r = $json->decode($res->content);
        if ('success' eq $api_r->{status}) {
            my $record_id = $api_r->{data}{record_id};
            print "$fqdn added as record ID $record_id\n";
            return 1;
        }
        print Dumper($res);
        return 0;
    };
    print Dumper($res->content);
    return 0;
};

sub get_zone_record {
    my ($self, $type, $zone, $fqdn) = @_;

    #  /[A|NS|MX|...]Record/<zone>/<FQDN>/
    $type = uc($type) . 'Record';
    $zone or die "missing zone ($type, $fqdn)\n";
    my $res = $self->get_api_response('GET', "$type/$zone/$fqdn/");
    if ($res->code == '404') {
        print "Host $fqdn doesn't exist\n";
        return 0;
    }

    if (!$res->is_success) {
        print "failed: " . Dumper($res);
        return 0;
    }

    my $r = $json->decode($res->content);
    if ('failure' eq $r->{status}) {
        if ($r->{msgs}[0]->{INFO} eq 'node: Not in zone') {
            print "failure: " . Dumper($r->{msgs});
        }
    }

    if ('success' eq $r->{status}) {
        print "$fqdn exists\n";
        return $r;
    }

    return 0;
}

sub publish_zone {
    my ($self, $zone) = @_;
    print "publishing zone $zone\n";
    my $r = $self->get_api_response('PUT', "Zone/$zone/", {publish => 1});
    print Dumper($r->content);
};

sub add_zone {
    my ($self, $zone) = @_;

    my $res = $self->get_api_response('POST', "Zone/$zone", {rname => 'hostmaster@'.$zone, ttl => 3600, 'serial_style' => 'day'});

    if ($res->is_success) {
        my $api_r = $json->decode($res->content);
        if ('success' eq $api_r->{status}) {
            print "$zone added, publishing\n";
            $self->publish_zone($zone);
            return 1;
        }
        return 0;
    };

# '{"status": "success", "data": {"zone_type": "Primary", "serial_style": "day", "serial": 0, "zone": "tnpi.net"}, "job_id": 917064873, "msgs": [{"INFO": "create: New zone tnpi.net created.  Publish it to put it on our server.", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}, {"INFO": "setup: If you plan to provide your own secondary DNS for the zone, allow notify requests from these IP addresses on your nameserver: 204.13.249.66, 208.78.68.66, 2600:2001:0:1::66, 2600:2003:0:1::66", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    print Dumper($res->content);
    return 1;
};

sub get_zone {
    my ($self, $zone) = @_;

    my $res = $self->get_api_response('GET', "Zone/$zone/");
    if ($res->code == '404') {
        print "Zone $zone doesn't exist\n";
        return 0;
    }
    if ($res->is_success) {
        my $api_r = $json->decode($res->content);
        if ('success' eq $api_r->{status}) {
            print "$zone exists\n";
            return 1;
        }
        return 0;
    };

    print Dumper($res->content);
    return 0;
}

sub delete_zone {
    my ($self, $zone) = @_;

    my $res = $self->get_api_response('DELETE', "Zone/$zone/");
    if ($res->code == '404') {
        print "Zone $zone doesn't exist\n";
        return 1;
    }
    if ($res->is_success) {
        my $api_r = $json->decode($res->content);
        if ('success' eq $api_r->{status}) {
            print "$zone deleted\n";
            return 1;
        }
        print Dumper($res);
        return 0;
    };

    print Dumper($res->content);
    return 0;
}

sub new_session {
    my ($self) = @_;

    my ($name, $user, $pass) = split /:/, $self->{nte}{ns_ref}{remote_login}, 3;
    my $req_args = {
        customer_name => $name,
        user_name     => $user,
        password      => $pass,
    };

    my $req = HTTP::Request->new('POST' => "${dyn_rest_url}Session/");
       $req->content_type('application/json');
       $req->content($json->encode($req_args));

    my $res = $ua->request($req);
# {"status": "success", "data": {"token": "k4sLb+YE5B7LLmACEb9oR1jPPPzFyQCCxmp23t06fUVtcHTV4d+HfaCsSIIguCWajwrw6tx3EQ+WGKXbcyhCJcX0g2hZjGjXJUZCHP5Rm6G80ABqR20ekk3XFT0qBL98zAqoZG0NLyuQrN1VQdVtLcVPL8iSBIW9", "version": "3.5.7"}, "job_id": 916926679, "msgs": [{"INFO": "login: Login successful", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    if ($res->is_success) {
        $self->{token} = $json->decode($res->content)->{data}{token};
        print "token: $self->{token}\n";
        return $self->{token};
    }

# TODO: catch and pass this error up to nameserver.status
    die "oops: " . $res->status_line, "\n";
    return 0;
}

sub end_session {

    my $ua_this = $ua->clone;
    my $api_url = $dyn_rest_url . 'Session/';
    my $res = $ua_this->delete($api_url);
    if ($res->is_success) {
        return $res->content;
    }

    die "oops: " . $res->status_line, "\n";
};

sub get_api_response {
    my ($self, $method, $rest_loc, $form_args) = @_; 

    if (!$self->{token}) { $self->new_session(); };

    my $api_url = $dyn_rest_url . $rest_loc;
    if ('/' ne substr($api_url, -1, 1)) { $api_url .= '/'; }
    print "API: $method $api_url: ";
    if ($form_args) { print Dumper($form_args); };

    my $req = HTTP::Request->new($method => $api_url);
       $req->content_type('application/json');
       $req->header( 'Auth-Token' => $self->{token} );

    if ($form_args) {
        $req->content($json->encode($form_args));
    }

    return $ua->request($req);
};

sub get_export_dir {
    return 1;  # not used
};

sub api_zr_soa {
    my ($self, $z) = @_;

warn "z: " . Dumper($z);

    # if missing, set a default mailaddr
    $z->{mailaddr} ||= 'hostmaster.' . $z->{zone} . '.';
    if ( '.' ne substr( $z->{mailaddr}, -1, 1) ) {   # not fully qualified
        $z->{mailaddr} = $self->{nte}->qualify( $z->{mailaddr} ); # append domain
        $z->{mailaddr} .= '.';     # append trailing dot
    };

my $api_r = $self->get_zone_record('SOA', $z->{zone}, $z->{name} || 'hostmaster');
warn Dumper($api_r);
}

sub api_zr_ns {
    my ($self, $r) = @_;

    my $zone = $self->{nte}{zone_name};
    my $name = $self->qualify( $r->{name} );

    return $self->add_zone_record( 'NS', $zone, $r->{name},
        { rdata => { nsdname => "$r->{address}" }, ttl => $r->{ttl} });
}

sub postflight {
    my $self = shift;
    return 1;
}

sub zr_a {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  A	$r->{address}\n";
}

sub zr_cname {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  CNAME	$r->{address}\n";
}

sub zr_mx {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  MX	$r->{weight}	$r->{address}\n";
}

sub zr_txt {
    my ($self, $r) = @_;
    if ( length $r->{address} > 255 ) {
        $r->{address} = join( "\" \"", unpack("(a255)*", $r->{address} ) );
    };
    return "$r->{name}	$r->{ttl}	IN  TXT	\"$r->{address}\"\n";
}

sub zr_ns {
    my ($self, $r) = @_;
    my $name = $self->qualify( $r->{name} );
    $name .= '.' if '.' ne substr($name, -1, 1);
    return "$name	$r->{ttl}	IN	NS	$r->{address}\n";
}

sub zr_ptr {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  PTR	$r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;
    $z->{mailaddr} ||= 'hostmaster.' . $z->{zone} . '.';
    if ( '.' ne substr( $z->{mailaddr}, -1, 1) ) {   # not fully qualified
        $z->{mailaddr} = $self->{nte}->qualify( $z->{mailaddr} ); # append domain
        $z->{mailaddr} .= '.';     # append trailing dot
    };
    return "
\$TTL    $z->{ttl};
\$ORIGIN $z->{zone}.
$z->{zone}.		IN	SOA	$z->{nsname}    $z->{mailaddr} (
					$z->{serial}    ; serial
					$z->{refresh}   ; refresh
					$z->{retry}     ; retry
					$z->{expire}    ; expiry
					$z->{minimum}   ; minimum
					)\n\n";
}

sub zr_spf {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  SPF	\"$r->{address}\"\n";
}

sub zr_srv {
    my ($self, $r) = @_;
    my $priority = $self->{nte}->is_ip_port( $r->{priority} );
    my $weight   = $self->{nte}->is_ip_port( $r->{weight} );
    my $port     = $self->{nte}->is_ip_port( $r->{other} );
    return "$r->{name}	$r->{ttl}	IN  SRV	$priority	$weight	$port	$r->{address}\n";
}

sub zr_aaaa {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  AAAA	$r->{address}\n";
}

sub zr_loc {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  LOC	$r->{address}\n";
}

sub zr_naptr {
    my ($self, $r) = @_;
    my $order = $self->{nte}->is_ip_port( $r->{weight}   );
    my $pref  = $self->{nte}->is_ip_port( $r->{priority} );
    my ($flags, $service, $regexp) = split /" "/, $r->{address};
    $regexp =~ s/"//g;  # strip off leading "
    $flags =~ s/"//g;   # strip off trailing "
    my $replace = $r->{description};
    $regexp =~ s/\\/\\\\/g;  # escape any \ characters
    return qq[$r->{name} $r->{ttl}   IN  NAPTR   $order  $pref   "$flags"  "$service"    "$regexp" $replace\n];
}

sub zr_dname {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  DNAME	$r->{address}\n";
}

sub zr_sshfp {
    my ($self, $r) = @_;
    my $algo   = $r->{weight};
    my $type   = $r->{priority};
    return "$r->{name} $r->{ttl}	IN  SSHFP   $algo $type $r->{address}\n";
}

sub zr_ipseckey {
    my ($self, $r) = @_;

    my $precedence = $r->{weight};
    my $gw_type    = $r->{priority};
    my $algorithm  = $r->{other};
    my $gateway    = $r->{address};
    my $public_key = $r->{description};

    return "$r->{name}	$r->{ttl}	IN  IPSECKEY	( $precedence $gw_type $algorithm $gateway $public_key )\n";
};

sub zr_dnskey {
    my ($self, $r) = @_;
    my $flags    = $r->{weight};
    my $protocol = $r->{priority};
    my $algorithm = $r->{other};
    return "$r->{name}	$r->{ttl}	IN  DNSKEY	$flags $protocol $algorithm $r->{address}\n";
}

sub zr_ds {
    my ($self, $r) = @_;
    my $key_tag     = $r->{weight};
    my $algorithm   = $r->{priority};
    my $digest_type = $r->{other};
    return "$r->{name}	$r->{ttl}	IN  DS	$key_tag $algorithm $digest_type $r->{address}\n";
}

sub zr_rrsig {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  RRSIG $r->{address}\n";
}

sub zr_nsec {
    my ($self, $r) = @_;
    $r->{description} =~ s/[\(\)]//g;
    return "$r->{name}	$r->{ttl}	IN  NSEC $r->{address} ( $r->{description} )\n";
}

sub zr_nsec3 {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  NSEC3 $r->{address}\n";
}

sub zr_nsec3param {
    my ($self, $r) = @_;
    return "$r->{name}	$r->{ttl}	IN  NSEC3PARAM $r->{address}\n";
}

1;

__END__

=head1 NAME

NicToolServer::Export::DynECT

=head1 SYNOPSIS

Export DNS information from NicTool to DynECT Managed DNS service.

=cut
