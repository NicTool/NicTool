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
   $ua->agent("NicTool/2.28");
#  $ua->ssl_opts(verify_hostname=>0);

my $json = JSON->new;

sub export_db {
    my ($self) = @_;

    # for incremental, get_ns_zones returns only changed zones.
    foreach my $z ( @{ $self->{nte}->get_ns_zones(publish_ts=>1) } ) {
        my $zone = $z->{zone};
        $self->{nte}->zones_exported($zone);
        $self->{nte}{zone_name} = $zone;
        if ($self->api_get("Zone/$zone/")) {
            $self->api_delete("Zone/$zone/");
        }

        my $zone_str = $self->{nte}->zr_soa( $z );
        # Dyn API strips the NS records, manually add later.
        #$zone_str .= $self->{nte}->zr_ns(  $z );

        foreach my $r ( @{ $self->get_records( $z->{nt_zone_id} ) } ) {
            my $method = 'zr_' . lc $r->{type};
            $r->{location}  ||= '';
            $zone_str .= $self->$method($r);  # inherited from Export::BIND
        }

        $self->add_zonefile($zone, $zone_str) or next;
       #$self->add_ns_records($z);           # manually add NS records
       #$self->remove_dyn_ns($zone);
        sleep 1;                     # wait a second, because
        $self->publish_zone($zone);  # immediate tries frequently fail
    }

    foreach my $z (@{$self->{nte}->get_ns_zones(publish_ts=>1,deleted=>1)}) {
        my $zone = $z->{zone};
        if ($self->{nte}->in_export_list($zone)) {
            $self->{nte}->elog("$zone recreated, skipping delete");
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

    $self->{nte}->set_copied(1);
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
        my $form = { ttl   => $ns_ref->{ttl},
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
        $self->{nte}->elog("GET host $fqdn doesn't exist");
        return 0;
    }

    if (!$res->is_success) {
        $self->{nte}->elog("failed: " . Dumper($res));
        return 0;
    }

    my $r = $json->decode($res->content);
    if ('failure' eq $r->{status}) {
        if ($r->{msgs}[0]->{INFO} eq 'node: Not in zone') {
            $self->{nte}->elog( "failure: " . Dumper($r->{msgs}));
        }
    }

    if ('success' ne $r->{status}) {
        $self->{nte}->elog( Dumper($r->{msgs}));
        return 0;
    }

    $self->{nte}->elog("GET $uri");
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
        $self->{nte}->elog("publish failed, retry");
        sleep 2;
        $res = $self->get_api_response('PUT', "Zone/$zone/", {publish => 1});
        if (!$res->is_success) {
            $self->{nte}->elog(Dumper($res));
            return 0;
        }
    };

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        $self->{nte}->elog(Dumper($api_r->{msgs}));
        return 0;
    }

    $self->{nte}->touch_publish_ts($zone);
    $self->{nte}->elog("published $zone");
    return 1;
};

sub add_zone {
    my ($self, $zone) = @_;

# '{"status": "success", "data": {"zone_type": "Primary", "serial_style": "day", "serial": 0, "zone": "tnpi.net"}, "job_id": 917064873, "msgs": [{"INFO": "create: New zone tnpi.net created.  Publish it to put it on our server.", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}, {"INFO": "setup: If you plan to provide your own secondary DNS for the zone, allow notify requests from these IP addresses on your nameserver: 204.13.249.66, 208.78.68.66, 2600:2001:0:1::66, 2600:2003:0:1::66", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    my $form = {rname => 'hostmaster@'.$zone, ttl => 3600, 'serial_style' => 'day'};
    return $self->api_add("Zone/$zone", $form);
};

sub api_get {
    my ($self, $path) = @_;

    my $res = $self->get_api_response('GET', $path);
    if ($res->code == '404') {
        $self->{nte}->elog("GET $path doesn't exist");
        return 0;
    }
    if (!$res->is_success) {
        $self->{nte}->elog( Dumper($res->content));
        return 0;
    }

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        $self->{nte}->elog( Dumper($api_r->{msgs}));
        return 0;
    }

    $self->{nte}->elog("GET $path");
    return $api_r->{data};
}

sub api_add {
    my ($self, $path, $req) = @_;

    my $res = $self->get_api_response('POST', $path, $req);
    if (!$res) {
        $self->{nte}->elog("FAIL: POST $path, $req");
        return 0;
    };

    if (!$res->is_success) {
        $self->{nte}->elog( Dumper($res->content));
        return 0;
    };

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        $self->{nte}->elog(Dumper($api_r->{msgs}));
        return 0;
    }

    $self->{nte}->elog("POST $path");
    return $api_r;
}

sub api_delete {
    my ($self, $path) = @_;

    my $res = $self->get_api_response('DELETE', $path);
    if ($res->code == '404') {
        $self->{nte}->elog("DELETE $path doesn't exist");
        return 1;
    }
    if (!$res->is_success) {
        $self->{nte}->elog(Dumper($res->content));
        return 0;
    }

    my $api_r = $json->decode($res->content);
    if ('success' ne $api_r->{status}) {
        $self->{nte}->elog(Dumper($api_r->{msgs}));
        return 0;
    }

    $self->{nte}->elog("DELETE $path");
    return 1;
}

sub remove_dyn_ns {
    my ($self, $zone) = @_;

    my $api_r = $self->get_zone_record('NS', $zone, $zone);
    if (!$api_r) {
        $self->{nte}->elog("no results");
        return;
    }

    foreach my $ns_uri ( @{ $api_r->{data}} ) {
# '/REST/NSRecord/simerson.net/simerson.net/112014785'
        my $id = (split(/\//, $ns_uri))[-1];
#       $self->{nte}->elog("id: $id");
        my $api_r2 = $self->get_zone_record('NS', $zone, $zone, $id);
        $self->{nte}->elog( Dumper($api_r2));
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

# {"status": "success", "data": {"token": "k4sLb+YE5B.....", "version": "3.5.7"}, "job_id": 916926679, "msgs": [{"INFO": "login: Login successful", "SOURCE": "BLL", "ERR_CD": null, "LVL": "INFO"}]}';

    $self->{token} = $json->decode($res->content)->{data}{token};
#   $self->{nte}->elog("token: $self->{token}");
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
        $self->{nte}->elog("API: $method $api_url: ");
        if ($form_args) { $self->{nte}->elog(Dumper($form_args)); };
    };

    my $req = HTTP::Request->new($method => $api_url);
       $req->content_type('application/json');
       $req->header( 'Auth-Token' => $self->{token} );

    if ($form_args) {
        $req->content($json->encode($form_args));
    }

    return $ua->request($req);
};

sub postflight { return 1; }

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::DynECT - export NicTool DNS data to DynECT managed DNS

=head1 VERSION

version 2.33

=head1 SYNOPSIS

Export authoritative DNS data to DynECT Managed DNS service.

=head1 NAME

NicToolServer::Export::DynECT

=head1 SEE ALSO

https://github.com/msimerson/NicTool/wiki/Export-to-DynECT-Managed-DNS

=head1 ACKNOWLEDGEMENTS

DynECT support funded by MivaMerchant and graciously donated to the NicTool project

=head1 AUTHORS

=over 4

=item *

Matt Simerson <msimerson@cpan.org>

=item *

Damon Edwards

=item *

Abe Shelton

=item *

Greg Schueler

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017 by The Network People, Inc. This software is Copyright (c) 2001 by Damon Edwards, Abe Shelton, Greg Schueler.

This is free software, licensed under:

  The GNU Affero General Public License, Version 3, November 2007

=cut
