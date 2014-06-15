package NicToolServer::Export::DynECT;
# ABSTRACT: export NicTool DNS data to DynECT managed DNS

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::BIND';

use Data::Dumper;
use JSON;
use LWP::UserAgent;

my $debug=0;
my $dyn_rest_url = 'https://api.dynect.net/REST/';

my $ua = LWP::UserAgent->new;
   $ua->agent("NicTool/2.24");
#  $ua->ssl_opts(verify_hostname=>0);

my $json = JSON->new;

sub export_db {
    my ($self) = @_;

    # for incremental, get_ns_zones returns only changed zones.
    foreach my $z ( @{ $self->{nte}->get_ns_zones() } ) {
        my $zone = $z->{zone};
        push @{$self->{zone_list}}, $zone;
        $self->{nte}{zone_name} = $zone;
        if ($self->api_get("Zone/$zone/")) {
            $self->api_delete("Zone/$zone/");
        }
        #$self->add_zone($zone);  # upload does this

        my $zone_str = $self->{nte}->zr_soa( $z );
        # Dyn API overrides NS records in zone files, manually add later.
        #$zone_str .= $self->{nte}->zr_ns(  $z );

        foreach my $r ( @{ $self->get_records( $z->{nt_zone_id} ) } ) {
            my $method = 'zr_' . lc $r->{type};
            $r->{location}  ||= '';
            $zone_str .= $self->$method($r);  # inherited from Export::BIND
        }

        $self->add_zonefile($zone, $zone_str) or next;
        $self->add_ns_records($z);           # manually add NS records
       #$self->remove_dyn_ns($zone);
        sleep 1;
        $self->publish_zone($zone);
    }

    foreach my $z ( @{ $self->{nte}->get_ns_zones( deleted => 1) } ) {
        my $zone = $z->{zone};
        if ( grep { $_ eq $zone } @{$self->{zone_list}} ) {
            warn "$zone was recreated, skipping delete\n";
            next;
        };
        if (!$self->api_get("Zone/$zone/")) {   # zone not published on Dyn
            next;
        };
        if ($self->api_delete("Zone/$zone/")) {
            $self->{nte}->elog("deleted $zone");
            $self->{nte}{zones_deleted}{$zone} = 1;
        }
        else {
            $self->{nte}->elog("error deleting $zone");
        }
    };

    $self->end_session();
    return 1;
}

sub add_zonefile {
    my ($self, $zone, $zone_str) = @_;
# https://help.dynect.net/upload-zone-file-api/
# TODO: check size of zone_str, and if larger than 1MB, split into multiple
# requests.
    return $self->api_add("ZoneFile/$zone/", { file => $zone_str });
};

sub add_ns_records {
    my ($self, $z) = @_;

    my $zone = $z->{zone};
    foreach my $nsid ( split(',', $z->{nsids} ) ) {
        my $ns_ref = $self->{nte}{active_ns_ids}{$nsid};
        my $form = { ttl   => $ns_ref->{ttl}
                     rdata => { nsdname => $self->qualify($ns_ref->{name}, $zone) },
                   };
        $self->api_add("NSRecord/$zone/$zone", $form);
    }
};

sub add_zone_record {
    my ($self, $type, $zone, $fqdn, $req) = @_;

    # https://api.dynect.net/REST/ARecord/<zone>/<FQDN>/
    $type = uc($type) . 'Record';

    return $self->api_add("$type/$zone/$fqdn", $req);
};

sub get_zone_record {
    my ($self, $type, $zone, $fqdn, $id) = @_;

    #  /[A|NS|MX|...]Record/<zone>/<FQDN>/[id]/
    $type = uc($type) . 'Record';
    $zone or die "missing zone ($type, $fqdn)\n";
    my $uri = "$type/$zone/$fqdn/";
    if ($id) { $uri .= "$id/"; }
    my $res = $self->get_api_response('GET', $uri) or return 0;
    if ($res->code == '404') {
        print "GET host $fqdn doesn't exist\n";
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

    if ('success' ne $r->{status}) {
        print Dumper($r->{msgs});
        return 0;
    }

    print "$fqdn exists\n";
    return $r;
}

sub get_node_list {
    my ($self, $zone) = @_;

# returns a list like this:
#   'simerson.net',
#   '_dmarc.simerson.net',
#   'mar2013._domainkey.simerson.net',
#   .....

    return $self->api_get("NodeList/$zone/");
}

sub get_all_records {
    my ($self, $zone) = @_;

# returns a list like this:
#   '/REST/CNAMERecord/simerson.net/www.simerson.net/112104837',
#   '/REST/LOCRecord/simerson.net/loc.home.simerson.net/112104878',
#   '/REST/SOARecord/simerson.net/simerson.net/112104833',
#   '/REST/MXRecord/simerson.net/simerson.net/112104836',

    return $self->api_get("AllRecord/$zone/");
}

sub publish_zone {
    my ($self, $zone) = @_;

    my $res = $self->get_api_response('PUT', "Zone/$zone/", {publish => 1});
    if (!$res->is_success) {
        warn "publish attempt failed, retrying.\n";
        sleep 2;
        $res = $self->get_api_response('PUT', "Zone/$zone/", {publish => 1});
        if (!$res->is_success) {
            print Dumper($res);
            return 0;
        }
    };

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        print Dumper($api_r->{msgs});
        return 0;
    }

    print "published $zone\n";
    return 1;
};

sub add_zone {
    my ($self, $zone) = @_;

    my $res = $self->get_api_response('POST', "Zone/$zone",
            {rname => 'hostmaster@'.$zone, ttl => 3600, 'serial_style' => 'day'});

    if (!$res->is_success) {
        print Dumper($res);
        return 0;
    };

# '{"status": "success", "data": {"zone_type": "Primary", "serial_style": "day", "serial": 0, "zone": "tnpi.net"}, "job_id": 917064873, "msgs": [{"INFO": "create: New zone tnpi.net created.  Publish it to put it on our server.", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}, {"INFO": "setup: If you plan to provide your own secondary DNS for the zone, allow notify requests from these IP addresses on your nameserver: 204.13.249.66, 208.78.68.66, 2600:2001:0:1::66, 2600:2003:0:1::66", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        print Dumper($api_r->{msgs});
        return 0;
    }

    print "$zone added\n";
    return 1;
};

sub api_get {
    my ($self, $path) = @_;

    my $res = $self->get_api_response('GET', $path);
    if ($res->code == '404') {
        print "GET $path doesn't exist\n";
        return 0;
    }
    if (!$res->is_success) {
        print Dumper($res->content);
        return 0;
    }

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        print Dumper($api_r->{msgs});
        return 0;
    }

    print "GET $path\n";
    return $api_r->{data};
}

sub api_add {
    my ($self, $path, $req) = @_;

    my $res = $self->get_api_response('POST', $path, $req);
    if (!$res) {
        print "FAIL: POST $path, $req\n";
        return 0;
    };

    if (!$res->is_success) {
        print Dumper($res->content);
        return 0;
    };

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        print Dumper($api_r->{msgs});
        return 0;
    }

    print "POST $path\n";
    return $api_r;
}

sub api_delete {
    my ($self, $path) = @_;

    my $res = $self->get_api_response('DELETE', $path);
    if ($res->code == '404') {
        print "DELETE $path doesn't exist\n";
        return 1;
    }
    if (!$res->is_success) {
        print Dumper($res->content);
        return 0;
    }

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        print Dumper($api_r->{msgs});
        return 0;
    }

    print "DELETE $path\n";
    return 1;
}

sub remove_dyn_ns {
    my ($self, $zone) = @_;

    my $api_r = $self->get_zone_record('NS', $zone, $zone);
    if (!$api_r) {
        print "no results";
        return;
    }

    foreach my $ns_uri ( @{ $api_r->{data}} ) {
# '/REST/NSRecord/simerson.net/simerson.net/112014785'
        my $id = (split(/\//, $ns_uri))[-1];
#       print "id: $id\n";
        my $api_r2 = $self->get_zone_record('NS', $zone, $zone, $id);
        print Dumper($api_r2);
# check $api_r2, if zone ends with dynect.net, remove it
       #$self->api_delete("NSRecord/$zone/$zone/$id/");
    }
};

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
    if (!$res->is_success) {
        $self->{nte}->set_status("last: FAILED login: " . $res->status_line);
        $self->{nte}->elog("unable to login in: " . $res->status_line);
        return 0;
    }

# {"status": "success", "data": {"token": "k4sLb+YE5B7LLmACEb9oR1jPPPzFyQCCxmp23t06fUVtcHTV4d+HfaCsSIIguCWajwrw6tx3EQ+WGKXbcyhCJcX0g2hZjGjXJUZCHP5Rm6G80ABqR20ekk3XFT0qBL98zAqoZG0NLyuQrN1VQdVtLcVPL8iSBIW9", "version": "3.5.7"}, "job_id": 916926679, "msgs": [{"INFO": "login: Login successful", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    $self->{token} = $json->decode($res->content)->{data}{token};
#   print "token: $self->{token}\n";
    return $self->{token};
}

sub end_session {
    my $self = shift;
    $ua->delete( $dyn_rest_url . 'Session/' );
    delete $self->{token};
    return;
};

sub get_api_response {
    my ($self, $method, $rest_loc, $form_args) = @_;

    if (!$self->{token}) { $self->new_session(); };
    if (!$self->{token}) { return; };

    my $api_url = $dyn_rest_url . $rest_loc;
    if ('/' ne substr($api_url, -1, 1)) { $api_url .= '/'; }

    if ($debug) {
        print "API: $method $api_url: ";
        if ($form_args) { print Dumper($form_args); };
    };

    my $req = HTTP::Request->new($method => $api_url);
       $req->content_type('application/json');
       $req->header( 'Auth-Token' => $self->{token} );

    if ($form_args) {
        $req->content($json->encode($form_args));
    }

    return $ua->request($req);
};

sub api_zr_soa {
    my ($self, $z) = @_;

    # if missing, set a default mailaddr
    $z->{mailaddr} ||= 'hostmaster.' . $z->{zone} . '.';
    if ( '.' ne substr( $z->{mailaddr}, -1, 1) ) {                # not FQDN
        $z->{mailaddr} = $self->{nte}->qualify( $z->{mailaddr} ); # append domain
        $z->{mailaddr} .= '.';     # append trailing dot
    };

#my $api_r = $self->get_zone_record('SOA', $z->{zone}, $z->{name} || 'hostmaster');
#warn Dumper($api_r);
}

sub api_zr_ns {
}

sub postflight { return 1; }

1;

__END__

=head1 NAME

NicToolServer::Export::DynECT

=head1 SYNOPSIS

Export authoritative DNS data to DynECT Managed DNS service.

=head1 SEE ALSO

https://github.com/msimerson/NicTool/wiki/Export-to-DynECT-Managed-DNS

=cut
