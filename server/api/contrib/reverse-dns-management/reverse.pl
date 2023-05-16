#!/usr/bin/perl

###
### Nictool Reverse DNS management tool
### 2018-03-01 Per Abildgaard Toft (per@minfejl.dk)
### Reverse Configuration file
### Code is inspired by other projects available in the Nictool contrib folder
###

use strict;
use warnings;
use Data::Dumper;
use NetAddr::IP;
use Switch;
use NicTool;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use URI::Escape;

###
### Server configuration
###

my $server = "localhost";
my $port = "8082";
my $protocol = "SOAP";
my $user = "user";
my $pass = "password";
my $nt_group_id = 1;
my @nt_groups = qw(2 3 4 5 6 7);

#Flag disable overwrite of existing records
my $overwrite = 0;

#Option to check ripe records and create missing
my $check_ripe = 0;



#RIPE API Configuration
my $ripehost =  "https://rest.db.ripe.net/";
my $ripe_mnt = "AS9158-MNT";
my $ripe_pw = "secret";
my $ripe_pw2 = "alternativeSecret"";
my $ttl = 86400;
#Description which will be updated in nictool
my $descr = "Updated by auto reverse";
my $reverse_zone = 'in-addr.arpa';
my @ns_list = qw(ns1.telenor.dk ns2.telenor.dk);



$|=1;  #turn autoflush on

my $basedir = '.';
my $configfile = "$basedir/CONFIG";

my @configAllowedTokens = ('HEXIP','NUMIP','MANUAL');
my %prefix;


my $debug=0;

#Flush Output buffer


my $nt = NicTool->new(
    server_host => $server,
    server_port => $port || 8082,
    protocol    => $protocol ,
);

my $r = $nt->login( username => $user, password => $pass );

if ( $nt->is_error($r) ) {
    print( "login failed: $r->{store}{error_msg}" );
    die;
}

open(CONFIG, $configfile) || die "Can not read $configfile: $!\n\n";
my $i = 0;

while(<CONFIG>) {
    $i++;

    chop;
    next if ( m/^(#|$)/ );
    my $line = $_;
    # print "LINE: [$line]\n";

    if($line = m/^([\d+\.?]+)\/(\d+)\s+(\S+)\s?(\S+)?/)
    {
       chomp($1,$2,$3);

        #check if Configuration token is allowed
        if($3 ~~ @configAllowedTokens)
        {
            #Load all configuration into hash with the prefix as key and the operation as value
            $prefix{"$1/$2"} = new NetAddr::IP("$1/$2");
            $prefix{"$1/$2"}{"type"} = "$3";
            #Check the FQDN and ensure there is a dot in the end
            if(defined($4))
            {
                chomp($4);
                check_fqdn($4);
                $prefix{"$1/$2"}{"domain"} = "$4";
            }
            else
            {
                print "Domain missing! row: [".$line."] \n";
                die;
            }

        } else {print "[CONFIG] Parse error: [".$line."] (Configuration [$3] not allowed!)\n"; die;}
    } else {print "[CONFIG] Parse error: [".$line."] \n";die;}
}

close CONFIG;
#Process Networks
if(!%prefix)
{
    die("No prefix found in configuration");
}
my %work;

foreach my $net (sort keys %prefix) {
    print "=== NET $net === \n";
    if($prefix{$net}->masklen() lt 16) {
        foreach my $net2 ($prefix{$net}->split(16)) {
            #print "RIPE lt 16 net: $net2 \n";
            my @z = split('\.',to_arpa($net2));
            my @tmp = splice @z, 1, scalar @z ;
            my $arpa16 = join('.',@tmp);
            print "arpa16: $arpa16 \n";
            ripe($arpa16);
        }
    }
    elsif ($prefix{$net}->masklen() eq 16) {
        #print "RIPE eq 16: ".$prefix{$net}. "\n";;
        my @z = split('\.',to_arpa($prefix{$net}));
        my @tmp = splice @z, 1, scalar @z ;
                 my $arpa16 = join('.',@tmp);
        print "arpa16: $arpa16 \n";
        ripe($arpa16);
    }
    elsif($prefix{$net}->masklen() gt 16) {

        #print "RIPE gt 16: \n";

        foreach my $n ($prefix{$net}->split(24)) {
            ripe(to_arpa($n));
        }
    }
    #Expand network in /16 and add to work hash
    foreach my $n ($prefix{$net}->split(24))
    {
        #print "Work add $prefix{$net} type: $prefix{$net}{type} domain: $prefix{$net}{domain} \n";
        $work{$n}{"type"} = $prefix{$net}{"type"};
        $work{$n}{"domain"} = $prefix{$net}{"domain"};
    }
}

print "Update zone files:\n";
foreach my $i (sort keys %work) {
    print $i." => ".$work{$i}{"type"}." => ".$work{$i}{domain}."\n";
    my $ip = new NetAddr::IP($i); # Subtract -1 to start with net address
    $ip++; #Skip network address

    while ($ip < $ip->broadcast) {

        switch($work{$i}{type}) {
            case "HEXIP"    {  update($work{$i}{domain},$ip->addr,hexip($ip->addr));            }
            case "NUMIP"    {  update($work{$i}{domain},$ip->addr,numip($ip->addr));            }
        }
        $ip ++;
    }
}

#   print $prefix{$net}{netaddr}->network()."\n";
#   print "NET: $net \t TYPE: $prefix{$net}{type}\t\t ZONE: ".to_arpa($net)."\n";
#   my $ip = new NetAddr::IP($net."/".$prefix{$net}{cidr}) -1; # Subtract -1 to start with net address
#   $ip++; #Skip network address


#print "IP: $ip \n";
#while ($ip < $ip->broadcast) {

#   switch($prefix{$net}{type})
#   {
#       case "HEXIP"    {  update($prefix{$net}{domain},$ip->addr,hexip($ip->addr));        }
#       case "NUMIP"    {  update($prefix{$net}{domain},$ip->addr,numip($ip->addr));        }
#   }
#  $ip ++;
#}

#blockip(217,157,0,0,2);
#}

sub ripe {
    my $arpa = shift;

    if($check_ripe ne 1) { return; }

    check_arpa_zone($arpa);

    print "Check Arpa: $arpa \n";
    my @z = split('\.',$arpa);

    #Check if we are working with /16
    if(scalar(@z) eq 4) {
        if (ripe_query($arpa) eq 1) {
            print "RIPE OK\n";
            return;
        }
    }
    else {
        my @tmp = splice @z, 1, scalar @z ;
        my $arpa16 = join('.',@tmp);

        #Ripe_query will return 1 on errors
        if(ripe_query($arpa16) eq 1) {
            if(ripe_query($arpa) eq 0) {
                print "RIPE OK\n";
            }
        }
    }
}


sub ripe_query {
    my $arpa = shift;


    if($check_ripe eq 0) { return ; }

    print "=== RIPE Check: ".$arpa." === \n";

    my $url_check = $ripehost."ripe/domain/".$arpa.".json";
    print "Fetching url: [$url_check]\n";

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->env_proxy;

    my $json;
    my $response = $ua->get($url_check);
    if ($response->is_success) {
        $json = $response->decoded_content;  # or whatever
    }
    else {
        print "Status line: ".$response->status_line."\n";
        if ($response->status_line =~ /404/) {
            print "404 not found error\n";
            ripe_create($arpa);
            return 0;
        }
    }

    if( !defined $json) {
        print "Could not fetch url: $url_check \n";
        return 1;
    }

    my $decoded = decode_json($json);

    ##print "JSON:[$json]\n";
    #print Dumper($decoded);

    if($decoded->{'errormessages'}) {
        print "[ERROR]Ripe did not return object!";
        die("!!!");
        return 1;
    }

    my $update=0;
    my $mntok=0;
    my @attribute;
    foreach(keys $decoded->{'objects'}{'object'}[0]{'attributes'}{'attribute'}) {

        my $obj = $decoded->{'objects'}{'object'}[0]{'attributes'}{'attribute'}[$_];

        # Strip all nserver and add later
        if($obj->{'name'} eq "nserver") {
            my $nsok=0;
    #       print "N: $obj->{value} \n";
            foreach my $n (@ns_list) {
                if($n eq $obj->{value}) {
                    $nsok=1;
                }
            }
            if($nsok eq 0) {
                print "Need NS update\n";
                $update=1;
            }
        }

        if($obj->{'name'} eq "mnt-by")
        {
            if($obj->{value} eq $ripe_mnt) {
                $mntok=1;
            }
        }
    }

    #Contstruct new attribute array
    foreach my $i (@{$decoded->{'objects'}{'object'}[0]{'attributes'}{'attribute'}}) {   #Remove nserver attrbutes
        if($i->{name} eq "nserver") {
            next;
        }
        if($i->{name} eq "last-modified") {
            next;
        }

        push @attribute, $i;
    }

    #Append ns list to new array
    foreach my $ns (@ns_list) {
        my $ns = {
            "name" => "nserver",
            "value" => $ns
        };
        push @attribute, $ns;
    }

    #mnt missing, add to object
    if($mntok eq 0) {
        print "Need mnt update\n";
        $update=1;
        my $mnt = {
           'link' => {
                'href' => 'http://rest.db.ripe.net/ripe/mntner/SONOFON-NOC',
                'type' => 'locator'
            },
           'value' => $ripe_mnt,
           'referenced-type' => 'mntner',
           'name' => 'mnt-by'
        };
        push @attribute, $mnt;
    }

    # print "==== Before:\n";
    # print Dumper($decoded);
    # print "ATTR".Dumper(@attribute);
    my $data = $decoded;
    $data->{'objects'}{'object'}[0]{'attributes'}{'attribute'} = \@attribute;

    # print "==== After:\n";
    # print Dumper($decoded);
    # print "=====\n";

    if ($update eq 1) {

        my $new_json = to_json($data,{utf8 => 1, pretty => 1});
        my $url_update = $ripehost."ripe/domain/$arpa";


        print "=======RIPE UPDATE =========\n";
        print "GET:\n $json \n";
        print "============================\n";
        print "PUT:\n".$new_json;
        print "uri:\n".$url_update."\n";
        print "============================\n";

        my $ua = LWP::UserAgent->new;
        $ua->timeout(20);
        $ua->env_proxy;

        my $post_url = $url_update."?password=".uri_escape($ripe_pw2)."&password=".uri_escape($ripe_pw);

        #print "uri:".$post_url."\n";
        my $req = HTTP::Request->new(PUT => $post_url);
        $req->header( 'Content-Type' => 'application/json' );
        $req->header( 'Accept' => 'application/json' );
        $req->content( $new_json );
        #$ua->post( $req );
        my $resp = $ua->request($req);
        my $message = $resp->decoded_content;
        my $decoded = decode_json($message);

        if ($resp->is_success) {
            print "Received reply: $message\n";
        }
        else {
            print "HTTP POST error code: ", $resp->code, "\n";
            print "HTTP POST error message: ", $resp->message, "\n";
            if ($decoded->{'errormessages'}) {

                foreach my $i (keys $decoded->{'errormessages'}{'errormessage'}) {
                    my $error = $decoded->{'errormessages'}{'errormessage'}[$i];
                    chomp($error->{text});
                    print "ERROR: ".$error->{text}."\n";
                }
            }

            if($resp->code eq 400) {
                print "ERROR: Could not update RIPE object\n";
                return 1;
            }
        }
    }
    else {
        print "Zone OK - no update required\n";
        return 0;
    }
}

sub ripe_create
{
    my $arpa = shift;
    print "RIPE Create object: $arpa\n";

    my $ripe = {
        "objects" => {
            "object"=> [
                {
                    "type" => "domain",
                    "source" => {
                        "id" => "ripe"
                    },
                    "primary-key" => {
                        "attribute" => [
                            {
                                "name" => "domain",
                                "value" => "$arpa"
                            }
                        ]
                    },
                    "attributes" => {
                        "attribute" => [
                            {
                                "name" => "domain",
                                "value" => "$arpa"
                            },
                            {
                                "name" => "descr",
                                "value" => "Telenor A/S"
                            },
                            {
                                "link" => {
                                    "type" => "locator",
                                    "href" => "http://rest.db.ripe.net/ripe/role/DMT2-RIPE",
                                },
                                "name" => "admin-c",
                                "value" => "DMT2-RIPE",
                                "referenced-type" => "role",
                            },
                            {
                                "link" => {
                                    "type" => "locator",
                                    "href" => "http://rest.db.ripe.net/ripe/role/DMT2-RIPE"
                                },
                                "name" => "tech-c",
                                "value" => "DMT2-RIPE",
                                "referenced-type" => "role"
                            },
                            {
                                "link" => {
                                    "type" => "locator",
                                    "href" => "http://rest.db.ripe.net/ripe/role/DMT2-RIPE"
                                },
                                "name" => "zone-c",
                                "value" => "DMT2-RIPE",
                                "referenced-type" => "role"
                            },
                            {
                                "name" => "nserver",
                                "value" => "ns1.telenor.dk"
                            },
                            {
                                "name" => "nserver",
                                "value" => "ns2.telenor.dk"
                            },
                            {
                                "name" => "mnt-by",
                                "value" => "SONOFON-NOC",
                                "referenced-type" => "mntner"
                            },
                            {
                                "name" => "mnt-by",
                                "value" => "$ripe_mnt",
                                "referenced-type" => "mntner"
                            },
                            {
                                "name" => "source",
                                "value" => "RIPE"
                            }
                        ]
                    }
                }
            ]
        }
    }

    my $json = to_json($ripe,{utf8 => 1, pretty => 1});

    print "=======RIPE CREATE =========\n";
    print $json;
    print "============================\n";


    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->env_proxy;
    my $url_create = $ripehost."ripe/domain?password=".uri_escape($ripe_pw2)."&password=".uri_escape($ripe_pw);
    print "Create URI:".$url_create."\n";

    my $req = HTTP::Request->new(POST => $url_create);
    $req->header( 'Content-Type' => 'application/json' );
    $req->header( 'Accept' => 'application/json' );
    $req->content( $json );

    my $resp = $ua->request($req);
    undef $json;
    $json = $resp->decoded_content;
    my $decoded;
    eval {
        $decoded = decode_json($json);
    } or do {
        print "JSON Decode error: $json \n";
        print "ERROR: ".$@."\n";
        return;
    };

    undef $json;
    if ($decoded->{'errormessages'}) {

        foreach my $i (keys $decoded->{'errormessages'}{'errormessage'}) {
            my $error = $decoded->{'errormessages'}{'errormessage'}[$i];
            chomp($error->{text});
            print "ERROR: ".$error->{text}."\n";
        }
    }

    if ($resp->is_success) {
        my $message = $resp->decoded_content;
        print "Received reply: $message\n";
    }
    else {
        print "HTTP POST error code: ", $resp->code, "\n";
        print "HTTP POST error message: ", $resp->message, "\n";

        if($resp->code eq 400) {
            print "ERROR: Could not create RIPE object\n";
            return;
            #die("Could not create RIPE object");
        }
    }
    return;
}


sub check_arpa_zone {
    my $arpa = shift or die("Missing zone in check_arpa_zone");
    print "Check Arpa: $arpa \n";

    my ($zid,$grp) = get_zone_id($arpa);
    if(! defined $zid) {
        print "Zone missing : $arpa \n";
        ($zid,$grp) = create_zone($arpa,$nt_group_id);
    }

    #my ($zid,$grp) = get_zone_id($arpa);
    print "Zone $arpa in group $grp has id $zid \n";
    return ($grp,$zid);
}

sub check_arpa_zone_backup {
    my $zone = shift or die("Missing zone in checl_arpa_zone");
    print "Check Arpa: $zone \n";
    my @z = split('\.',$zone);
    my @tmp = splice @z, 1, scalar @z ;
    my $arpa16 = join('.',@tmp);

    if(scalar @z eq 4) #/16 {

        my ($zid16,$grp16) = get_zone_id($arpa16);
        if(! defined $zid16) {
            print "Zone missing 16: $arpa16 \n";
            ($zid16,$grp16) = create_zone($arpa16,$nt_group_id);
        }

        my ($zid,$grp) = get_zone_id($zone);
        print "Zone /16 $arpa16 in group $grp16 has id $zid16 \n";

    }
        #elsif(scalar @z eq 5) #/24
    else {
        #  my $zid = get_zone_id($zone);

        my ($zid16,$grp16) = get_zone_id($arpa16);
        if(! defined $zid16) {
            print "Zone missing 16: $arpa16 \n";
            ($zid16,$grp16) = create_zone($arpa16,$nt_group_id);
        }

        my ($zid,$grp) = get_zone_id($zone);
        if(! defined $zid) {
            print "Zone missing: $zone \n";
            ($zid,$grp) = create_zone($zone,$nt_group_id);
        }
        if(! defined $zid) {
            die("Could not get  r create zone $zone");
        }
        if(! defined $zid16) {
            die("Could not get  r create zone $zone");
        }

        print "Zone $zone has id $zid  in group $grp and the /16 $arpa16 in group $grp16 has id $zid16 \n";
    }
}



sub fix_reverse_zones {
    my $zone = shift or die("fix_reverse_zones( zone ) required!");
}

sub update {
    my($zone,$ip,$address) = @_;
    my ($a,$b,$c,$host) = split(/\./,$ip);
    my $fqdn = $address.".".$zone.".";

    print "\n######################## Update #######################\n";
    print "Zone: $zone\n";
    print "IP: $ip\n";
    print "Address: $address\n";
    print "FQDN: $fqdn\n";

    #Update forward zone
    print "\n################ Forward DNS ##################\n";
    my $now = get_zone_records($zone,$address);

    if ( $now ) {
        my %new = %$now;
        #Update info
        $new{address} = $ip;
        $new{description} = "Updated by auto reverse";
        $new{ttl} = $ttl;
        warn "$address record exists ip: ".$new{address}."\n";
        if ($overwrite eq 1) {
            update_record( \%new, $now );     # update the $host record
        }
        else {
            print "Warning: Overwrite is disabled\n";
        }
    }
    else {
        print "Creating new record...\n";
        create_forward( $address, $zone, $ip, "A" );
    }
    undef $now;
    print "\n################ Reverse DNS ##################\n";

    #Update Reverse zone
    $now = get_reverse_zone_record($ip);  # find the reverse zone
    if ( $now ) {
        my %new = %$now;
        $new{address} = $fqdn;
        $new{ttl} = $ttl;
        print "Reverse record exists ".$new{address}." - update to: $fqdn \n";
        if($overwrite eq 1) {
            update_record( \%new, $now );           # update the PTR
        }
        else {
            print "Warning: Overwrite is disabled\n";
        }

    }
    else {
        print "Createing record $ip \t $fqdn \n";
        create_ptr( $ip, $fqdn);
    }
    print "###################################################\n\n";
}

sub create_zone {
    my ( $zone, $nt_group_id ) = @_;
    print "Creating zone $zone in group $nt_group_id \n";

    $zone or die ("No zone given\n");
    $nt_group_id or die ("No nt_group_id given\n");

    my $r = $nt->new_zone(
        nt_zone_id  => undef,
        nt_group_id => $nt_group_id,
        zone        => $zone,
        ttl         => 3600,
        serial      => undef,
        nameservers => '2,3',
        mailaddr => 'hostmaster.'.$zone,
        refresh  => 10800,
        retry    => 3600,
        expire   => 604800,
        minimum  => 3600
    );

    # my $r = $nt->new_zone_record(
    #     nt_zone_id  => undef,
    #     nt_group_id     => $nt_group_id,
    #     zone        => $zone,
    #     nameservers     => join(",",@ns_list)
    # );

    if ( $r->{store}{error_code} != 200 ) {
        warn ("$r->{store}{error_desc} ( $r->{store}{error_msg} )" );
        return;
    }
    my $zone_id = $r->{store}{nt_zone_id};
    return ($zone_id,$nt_group_id);
}

sub create_forward {
    my ( $host, $zone, $ip, $type ) = @_;
    print "Create forward record host: $host zone: $zone ip: $ip type: $type \n" if($debug);

    $host or die ("No host given\n");
    $zone or die ("No zone given\n");
    $type or die ("No type given\n");
    $ip or die ("No ip given\n");

    my ($zone_id,$grp_id) = get_zone_id( $zone )
        or die("did not find zone $zone in NicTool");
    create_record( {
        nt_zone_id  => $zone_id,
        ttl         => $ttl,
        type        => $type,
        name        => $host,
        address     => $ip,
        description => $descr,
    } )
    or die("failed to create $type for $host.$zone");

    print("created $type $host $zone $ip");
    return 1;
}

sub create_ptr {
    my ( $ip, $address ) = @_;

    my ($rev_zone, $host_addr) = get_reverse('zone', $ip )
        or die("unable to compute rDNS zone for $ip");

    my ($zone_id,$grp_id) = get_zone_id( $rev_zone ) or return;

    create_record( {
        nt_zone_id  => $zone_id,
        ttl         => $ttl,
        type        => 'PTR',
        name        => $host_addr,
        address     => $address,
        description => $descr,
    } )
    or die ("failed to create PTR for $ip");
    print "created $ip PTR $address";
    return 1;
}

sub get_reverse {
    my ($type, $ip) = @_;

    $ip or die "missing IP in request\n";

    if ( $ip =~ /:/ ) {  # test for IPv6
        die;
    }

    my @octets = split /\./, $ip;
    if ( $type eq 'zone' ) {
        return ("$octets[2].$octets[1].$octets[0].$reverse_zone", $octets[3]);
    }
    elsif ( $type eq 'address' ) {
        return "$octets[3].$octets[2].$octets[1].$octets[0].$reverse_zone.";
    }
    else {
        die "unknown reverse type: $type\n";
    };
}


#Unused
sub create_record {
    my $args = shift;
    # check for required fields
    foreach my $must ( qw/ nt_zone_id ttl type name address / ) {
        die "missing field $must in request" if ! defined $args->{$must};
    };
    # foreach my $optional ( qw/ description / ) {
    #     warn if ! defined $args->{$optional};
    # };

    # create it
    my $r = $nt->new_zone_record(
            nt_zone_id  => $args->{nt_zone_id},
            ttl         => $args->{'ttl'},
            type        => $args->{'type'},
            name        => $args->{'name'},
            address     => $args->{'address'},
            description => $args->{'description'},
    );

    if ( $r->{store}{error_code} != 200 ) {
        warn ("$r->{store}{error_desc} ( $r->{store}{error_msg} )" );
        return;
    }

    print( "record created.\n" );
    return 1;
}

sub update_record {
    my ( $new_ref, $now_ref ) = @_;

    # check for required fields
    foreach my $must ( qw/ nt_zone_id nt_zone_record_id type name address / ) {
        die if ! defined $new_ref->{$must};
    };

    my $changes=0;
    my @fields = qw/ name address type ttl weight priority other description /;
    foreach my $f (@fields) {
        my $new = $new_ref->{$f};
        my $now = $now_ref->{$f};
        next if ! defined $new && ! defined $now;
        print "$f: [$new] ne [$now] \n" if($debug);
        if ( $new ne $now ) {
            $changes++;
            chomp($new,$now);
            print  "==>Change DNS record $f '$now' to '$new'\n";
        }
    }

    if ( !$changes ) {
        print ( "No changes requested (".$now_ref->{address}.")\n" );
        return;
   }
   my %req = (
        nt_zone_id        => $new_ref->{nt_zone_id},
        nt_zone_record_id => $new_ref->{nt_zone_record_id},
        'name'            => $new_ref->{name},
        'address'         => $new_ref->{address},
        'type'            => $new_ref->{type},
        'ttl'             => $new_ref->{ttl} || $ttl,
        'weight'          => $new_ref->{weight},
        'priority'        => $new_ref->{priority},
        'other'           => $new_ref->{other},
        'description'     => $new_ref->{description} || $descr,
    );
    my $r = $nt->edit_zone_record(%req);


    if ( $r->{store}{error_code} != 200 ) {
        print( "$r->{store}{error_desc} ( $r->{store}{error_msg} )" );
        return;
    }

    return 1;
}

sub get_reverse_zone_record {
    my $ip = shift or die "missing IP in request\n";
    my $rsuffix = shift;

    my @octets = split /\./, $ip;
    my ($zone, $host) = get_reverse('zone', $ip, $rsuffix);

    # my ($zoneid, $grpid) = check_arpa_zone($zone);

    my $zoneid = get_zone_id($zone);
    if( !$zoneid ) {
        print("Zone $zone not found");
        $zoneid = create_zone($zone,$nt_group_id);
        print "Zone created with zone id: ".$zoneid."\n";
    }

    print("Searching for zone [$zone]\n") if($debug);
    return get_zone_records($zone,$octets[3]);
}


sub get_zone_records_advanced {
    my ( $zone_id, $name, $type ) = @_;

    my %request = (
        'nt_zone_id' => $zone_id,
        'Search'     => 1,
    );

    if ( $name ) {
        $request{'1_field'}  = 'name';
        $request{'1_option'} = 'equals';
        $request{'1_value'}  = $name;
    }
    if ( $type ) {
        $request{'2_inclusive'} = 'And';
        $request{'2_field'}     = 'type';
        $request{'2_option'}    = 'equals';
        $request{'2_value'}     = $type;
    }

    my $r = $nt->get_zone_records(%request);


    return if !$r->{store}{records};

    if ( $debug ) {

        for ( my $i = 0; $i < scalar( @{ $r->{store}{records} } ); $i++ ) {
        print "i: $i \n";
            next unless defined $r->{store}{records}[$i]{store};
            print ( $r->{store}{records}[$i]{store}{name}.",".$r->{store}{records}[$i]{store}{type}.",". $r->{store}{records}[$i]{store}{address} );
        }

        warn "get_zone_records: returning $r->{store}{records}\n";
    }

    if ( $name ) {
        if ( $r->{store}{records}[1]{store} ) {
            warn( "yikes, more than one record matched?!" );
        }
        return $r->{store}{records}[0]{store};
    }

    my @records;
    foreach ( @{ $r->{store}{records} } ) {
        push @records, $_->{store};
    }
    return \@records;
}


sub get_zone_records {
    my ( $zone, $host ) = @_;

    my ($zone_id,$group_id) = get_zone_id($zone);

    my %req = (
        'nt_zone_id'    =>$zone_id,
        'Search'        => 1,
        '1_field'       => 'name',
        '1_option'      => 'equals',
        '1_value'       => $host
        );

    my $r = $nt->get_zone_records(%req );

    return if !$r->{store}{records};

    if($debug) {
        print "=== Result from get_zone_records: ===  \n";
        for ( my $i = 0; $i < scalar( @{ $r->{store}{records} } ); $i++ ) {
            next unless defined $r->{store}{records}[$i]{store};
            printf("%5s  %5s  %35s\n", $r->{store}{records}[$i]{store}{name},
                $r->{store}{records}[$i]{store}{type},
                $r->{store}{records}[$i]{store}{address}) ;
        }
        print "============== end ===============\n";
    }

    if ( $r->{store}{records}[1]{store} ) {
        die( "yikes, more than one record matched?!" );
    }
    return $r->{store}{records}[0]{store};

    my @records;
    foreach ( @{ $r->{store}{records} } ) {
        push @records, $_->{store};
    }
    return \@records;
}

sub get_zone_id {
    my $zone = shift;
    chomp($zone);

    print "== Search for zone $zone == \n";
    foreach my $nt_group_id (@nt_groups) {
        # Obtain zone id
        my $r = $nt->get_group_zones(
            nt_group_id       => $nt_group_id,
            include_subgroups => 1,
            Search            => 1,
            '1_field'         => 'zone',
            '1_option'        => 'equals',
            '1_value'         => $zone,
        );

        if ( $r->{store}{error_code} != 200 ) {
            warn ("$r->{store}{error_desc} ( $r->{store}{error_msg} )");
        }

        if ($r->{store}{zones}[0]{store}{nt_zone_id}) {
            print "Found zone $zone in group $nt_group_id with id: ".$r->{store}{zones}[0]{store}{nt_zone_id}."\n";

            my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id};
            if( ! defined $zone_id) {
                warn "Could not fetch zone id in get_zone_id($zone)\n";
            }
            return ($zone_id, $nt_group_id);
        }
        # my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id} or do {
        # warn( "zone ($zone) not found!" );
        # return -1;
        # };
    }
    return;
}

sub new_zone {
    my $zone = shift;

    # Obtain zone id
    my $r = $nt->get_group_zones(
        nt_group_id       => $nt_group_id,
        'zone'         => 'zone',
    );

    if ( $r->{store}{error_code} != 200 ) {
        warn ("$r->{store}{error_desc} ( $r->{store}{error_msg} )");
        return -1;
    }

    my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id} or do {
       # warn( "zone ($zone) not found!" );
        return -1;
    };
    return $zone_id;
}


#Return reverse arpa notation from IP address
sub to_arpa {
   my $ip = shift;
   my ($a,$b,$c,$d) = split(/\./,$ip);

   return "$c.$b.$a.in-addr.arpa";
}

# Chech for vvalid FQDN
sub check_fqdn {
    my $fqdn = shift;

    if($fqdn !~ /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/) {
        die("CONFIG ERROR: Hostname incorrect. Example: adsl.teelnor.dk. (Remeber the dot)");
    }
    return 0;
}

#Algorithm which returns hexed IP notation
sub hexip {
    my $ip = shift;
    my ($i, $j) = (0, 0);
    my ($cpad, $dpad) = ("0", "0");

    my ($a,$b,$c,$d) = split(/\./,$ip);

    if ($c < 16) {
        $cpad = "0";
    }
    else {
        $cpad = '';
    }

    if ($d < 16) {
        $dpad = "0";
    } else {
        $dpad = '';
    }

    return sprintf "0x%x%x%s%x%s%x", $a, $b, $cpad, $c, $dpad, $d;
}

#Algorithm which returns Numerical IP notation
sub numip {
    my $ip = shift;

    my ($a,$b,$c,$d) = split(/\./,$ip);

    return sprintf "%03d%03d%03d%03d", $a, $b, $c, $d;
}

#my $ip = new Net::IP ($net."/".$prefix{$net}{cidr}) or die (Net::IP::Error());;
#print ("IP  : ".$ip->ip()."\n");
#print ("Last: ".$ip->last_ip()."\n");
#
##Zone name = $ip->reverse_ip()."\n");
#
#  # Loop
# while(++$ip)
# {
#   if ($ip->bincomp('gt',($ip->last_ip()))) {
#       print "ip";
#   }
#      print $ip->ip(), "\n";
#  }
#}

sub blockip {
    my ($a, $b, $c, $d,$end) = @_;
    my ($i, $j) = (0, 0);
    my ($ipad, $jpad) = ("0", "0");

    for ($i = $c; $i <= $end; $i++) {
        if ($i < 16) {
            $ipad = "0";
            #$ipad = '';
        } else {
            $ipad = '';
        }
        for ($j = 0; $j <= 255; $j++) {
            my $ip = "$a\.$b\.$i\.$j";

            if ($j < 16) {
                $jpad = "0";
            } else {
                $jpad = '';
            }
            my $host = sprintf "0x%x%x%s%x%s%x", $a, $b, $ipad, $i, $jpad, $j;
            print "$host\t\t\tA\t$ip\n";
            #$reverse{$ip} = check_reverse($ip, "${host}.${zonename}.");
         }
    }
}
