package NicToolServer::Import::tinydns;
# ABSTRACT: import tinydns data into NicTool

use strict;
use warnings;

use lib 'lib';
#use base 'NicToolServer::Import::Base';

use Cwd;
use Data::Dumper;
use English;
use File::Copy;
use Params::Validate qw/ :all /;
use Time::TAI64 qw/ unixtai64 /;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
};

sub get_import_file {
    my $self = shift;
    my $filename = shift || 'data';

    return $self->{FH} if defined $self->{FH};

    open my $FH, '<', $filename
        or die "failed to open '$filename'";

    $self->{FH} = $FH;
    return $FH;
};

sub import_records {
    my $self = shift;
    $self->get_import_file( 'data' ) or return;

# tinydns-data format: http://cr.yp.to/djbdns/tinydns-data.html

    my $fh = $self->{FH};
    while ( defined ( my $record = <$fh> ) ) {
        next if $record =~ /^#/;     # comment 
        next if $record =~ /^\s+$/;  # blank line 
        next if $record =~ /^\-/;       #  IGNORE     =>  - fqdn : ip : ttl:timestamp:lo

        my $first = substr($record, 0, 1 );
        my $record = substr($record, 1 );

        if ( $first eq 'Z' ) {          #  SOA        =>  Z fqdn:mname:rname:ser:ref:ret:exp:min:ttl:time:lo
            $self->zr_soa($record);
        }
        elsif ( $first eq '.' ) {       #  'SOA,NS,A' =>  . fqdn : ip : x:ttl:timestamp:lo
            $self->zr_soa($record);
            $self->zr_ns($record);
            $self->zr_a($record);
        }
        elsif ( $first eq '=' ) {       #  'A,PTR'    =>  = fqdn : ip : ttl:timestamp:lo
            $self->zr_a($record);
            $self->zr_ptr($record);
        }
        elsif ( $first eq '&' ) {       #  NS         =>  & fqdn : ip : x:ttl:timestamp:lo
            $self->zr_ns($record);
        }
        elsif ( $first eq '^' ) {       #  PTR        =>  ^ fqdn :  p : ttl:timestamp:lo
            $self->zr_ptr($record);
        }
        elsif ( $first eq '+' ) {       #  A          =>  + fqdn : ip : ttl:timestamp:lo
            $self->zr_a($record);       
        }
        elsif ( $first eq 'C' ) {       #  CNAME      =>  C fqdn :  p : ttl:timestamp:lo
            $self->zr_cname($record);
        }
        elsif ( $first eq '@' ) {       #  MX         =>  @ fqdn : ip : x:dist:ttl:timestamp:lo
            $self->zr_mx($record);
        }
        elsif ( $first eq '\'' ) {      #  TXT        =>  ' fqdn :  s : ttl:timestamp:lo
            $self->zr_txt($record);
        }
        elsif ( $first eq ':' ) {       #  GENERIC    =>  : fqdn : n  : rdata:ttl:timestamp:lo
            $self->zr_generic($record);
        }
        ;

        print "doing record $record";
    };

    print "done\n";
};

sub zr_a {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $ip, $ttl, $timestamp, $location ) = split(':', $r);


}

sub zr_cname {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $host, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_mx {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $ip, $addr, $distance, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_txt {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $addr, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_ns {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $ip, $host, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_ptr {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $fqdn, $address, $ttl, $timestamp, $location ) = split(':', $r);
}

sub zr_soa {
    my $self = shift;
    my $r = shift or die;

    print "$r";
    my ( $zone, $mname, $rname, $serial, $refresh, $retry, $expire, $min, $ttl, $timestamp, $location ) = split(':', $r);
}


sub nt_create_record {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone_id'     => { type => SCALAR },
            'name'        => { type => SCALAR },
            'address'     => { type => SCALAR },
            'type'        => { type => SCALAR },
            'ttl'         => { type => SCALAR, optional => 1, },
            'weight'      => { type => SCALAR, optional => 1, },
            'other'       => { type => SCALAR, optional => 1, },
            'priority'    => { type => SCALAR, optional => 1, },
            'description' => { type => SCALAR, optional => 1, },
        }
    );

    my %request = (
        nt_zone_id => $p{zone_id},
        name       => $p{name},
        address    => $p{address},
        type       => $p{type},
    );

    $request{ttl}         = $p{ttl}         if $p{ttl};
    $request{weight}      = $p{weight}      if defined $p{weight};
    $request{priority}    = $p{priority}    if defined $p{priority};
    $request{other}       = $p{other}       if defined $p{other};
    $request{description} = $p{description} if $p{description};

    # create it
    my $nt = $self->nt_connect();
    my $r = $nt->new_zone_record(%request);

    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }

    my $record_id = $r->{store}{nt_zone_record_id} || 1;
    return $record_id;
}

sub nt_get_zones {
    my $self = shift;

    my %p = validate(
        @_,
        {   'zone'  => { type => SCALAR },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
        }   
    );      
            
    #warn "getting zone $p{zone}"; 

    my $nt = $self->nt_connect();

    my $r = $nt->get_group_zones(
        nt_group_id       => $nt->{user}{store}{nt_group_id},
        include_subgroups => 1,
        Search            => 1,
        '1_field'         => 'zone',
        '1_option'        => 'equals',
        '1_value'         => $p{zone},
    );  
    
    #warn Data::Dumper::Dumper($r);
    
    if ( $r->{store}{error_code} != 200 ) {
        die "$r->{store}{error_desc} ( $r->{store}{error_msg} )";
    }   
    
    if ( !$r->{store}{zones}[0]{store}{nt_zone_id} ) {
        warn "\tzone $p{zone} not found!";
        return;
    }   
        
    my $zone_id = $r->{store}{zones}[0]{store}{nt_zone_id};
    return $zone_id;
}

sub nt_connect {
    my $self = shift;
    my ($nt_host, $nt_port, $nt_user, $nt_pass) = @_;

    return $self->{nt} if $self->{nt};

    eval { require NicTool; };

    if ($EVAL_ERROR) {
        die "Could not load NicTool.pm. Are the NicTool client libraries",
            " installed? They can be found in the api directory in ",
            " the NicToolServer distribution. See http://nictool.com/";
    }

    my $nt = NicTool->new(
            server_host => $nt_host || 'localhost',
            server_port => $nt_port || 8082,
#protocol    => 'xml_rpc',  # or soap
            );

    my $r = $nt->login( username => $nt_user, password => $nt_pass );

    if ( $nt->is_error($r) ) {
        die "error logging in to nictool: $r->{store}{error_msg}\n";
    }

    $self->{nt} = $nt;
    return $nt;
}

1;

