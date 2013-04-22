package NicToolServer::Zone::Record::Sanity;
# ABSTRACT: sanity tests for zone records

use strict;
use Net::IP;

@NicToolServer::Zone::Record::Sanity::ISA = qw(NicToolServer::Zone::Record);

sub new_zone_record {
    my ( $self, $data ) = @_;
    my $error = $self->new_or_edit_basic_verify($data);
    return $error if $error;

    # do any new_zone_record specific checks here

    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::new_zone_record($data);
}

sub edit_zone_record {
    my ( $self, $data ) = @_;
    my $zr = $self->get_zone_record($data);
    return $zr if $zr->{error_code} ne 200;
    $data->{nt_zone_id} = $zr->{nt_zone_id};
    foreach (qw(type address)) {
        $data->{$_} = $zr->{$_} unless exists $data->{$_};
    }
    my $error = $self->new_or_edit_basic_verify($data);
    return $error if $error;

    # do any edit_zone_record specific checks here
    $self->push_sanity_error( 'nt_zone_record_id',
        "Cannot edit deleted record!" )
        if $self->check_object_deleted( 'zonerecord',
                $data->{nt_zone_record_id} )
            and $data->{deleted} ne '0';
    return $self->throw_sanity_error if $self->{errors};

    return $self->SUPER::edit_zone_record($data);
}

sub new_or_edit_basic_verify {
    my ( $self, $data ) = @_;

    my $z = $self->find_zone( $data->{nt_zone_id} ) or
        $self->error( 'nt_zone_id', 'invalid zone_id' );

    if ( $self->check_object_deleted( 'zone', $data->{nt_zone_id} ) ) {
        $self->push_sanity_error( 'nt_zone_id',
            "Cannot create/edit records in a deleted zone." );
    }

    my $zone_text = $z->{zone};

    $self->_expand_shortcuts( $data, $zone_text );  # expand @ and & shortcuts

    if ( $data->{name} =~ /^(.+)\.$zone_text\.$/ ) {  # ends in domain name
        $data->{name} = $1; # strip domain. record names are NOT stored absolute
    }

    $self->_valid_rr_type($data);
    $self->_valid_name_chars( $data, $zone_text );  # check for invalid chars
    $self->_valid_name( $data, $zone_text );        # validate name pattern

    $self->_valid_cname($data, $zone_text)   if $data->{type} eq 'CNAME';
    $self->_valid_a($data, $zone_text)       if $data->{type} eq 'A';
    $self->_valid_aaaa($data, $zone_text)    if $data->{type} eq 'AAAA';
    $self->_valid_srv($data, $zone_text )    if $data->{type} eq 'SRV';
    $self->_valid_ns( $data, $zone_text )    if $data->{type} eq 'NS';
    $self->_valid_mx( $data, $zone_text )    if $data->{type} eq 'MX';
    $self->_valid_ptr($data, $zone_text )    if $data->{type} eq 'PTR';

    $self->_name_collision($data, $z);

    # check the record's TTL
    $data->{ttl} = 86400 if ( !$data->{ttl} && !$data->{nt_zone_record_id} );
    $self->valid_ttl( $data->{ttl} ) if defined $data->{ttl};

    return $self->throw_sanity_error if $self->{errors};
}

sub record_exists {
    my ( $self, $record, $record_type, $zone_id, $rid ) = @_;

    my $sql = "SELECT r.*, t.name AS type
    FROM nt_zone_record r
    LEFT JOIN resource_record_type t ON r.type_id=t.id
      WHERE r.deleted=0
        AND t.name=?
        AND r.nt_zone_id = ?
        AND r.name = ?";

    $sql .= " AND r.nt_zone_record_id <> $rid" if $rid;
    my $zrs = $self->exec_query( $sql, [ $record_type, $zone_id, $record ] );

    return ref( $zrs->[0] ) ? 1 : 0;
}

sub _name_collision {
    my ($self, $data, $z) = @_;

    my $zone_text = $z->{zone};

# check to make sure a sub-domain in zones doesn't clobber a record that user is trying to add/edit..

    return if $data->{name} =~ /$zone_text\.$/;
# we're here, so name is something like blah, or blah.blah

# if zone is zone.com., it's the origin, which should have already been checked
# for subdomain collisions. If it isn't, check ...
# split input in case it's like blah.blah.blah.zone.com and blah.blah.zone.com exists as a domain.
    my @nparts = split( /\./, $data->{name} );
    my @tocheck;
    my $basestr = $zone_text;
    while ( my $x = pop(@nparts) ) {
        $basestr = $x . "." . $basestr;
        push( @tocheck, $basestr );
    }
    @tocheck = reverse(@tocheck);
    while ( my $name = pop(@tocheck) ) {

        #warn "checking if exists $name";
        if ( $self->zone_exists( $name, 0 ) ) {
            $self->error( 'name',
                "Cannot create/edit Record '$data->{name}' in zone '$z->{zone}': it conflicts with existing zone '$name'."
            );
            last;
        }
    }
# TODO - make the above not so nasty
}

sub _expand_shortcuts {
    my ( $self, $data, $zone_text ) = @_;

    # expand any @ symbol shortcuts
    if ( $data->{name} =~ /\.\@$/ )
    {    # replace something.@ with something.zone name
        $data->{name} =~ s/\.\@$//;
        $data->{name} = $data->{name} . ".$zone_text.";
    }

    if ( $data->{name} eq '@' ) {    # replace @ with zone name
        $data->{name} = "$zone_text.";
    }

    if ( $data->{address} =~ /\.\@$/ )
    {    # replace something.@ with something.zone name
        $data->{address} =~ s/\.\@$//;
        $data->{address} = $data->{address} . ".$zone_text.";
    }

    if ( $data->{address} eq '@' ) {    # replace @ with zone name
        $data->{address} = "$zone_text.";
    }

    # expand the & shortcut
    if ( $data->{address} =~ /\.\&$/ )
    {    # replace something.& with something.in-addr.arpa.
        $data->{address} =~ s/\.\&$//;
        $data->{address} = $data->{address} . ".in-addr.arpa.";
    }

    # no return, changes are made to the original hash via reference
}

sub _valid_name_chars {
    my ( $self, $data, $zone_text ) = @_;

    return if ! defined $data->{name};  # an edit may not have this defined

    my $invalid_match = $self->get_invalid_chars( $data->{type}, 'name', $zone_text );

    return if $data->{name} !~ m/($invalid_match)/;  # no ickies

    # wildcard records: RFC 1034, 4592
    return if $data->{name} eq '*';       # wildcard *
    return if $data->{name} =~ /^\*\./;   # wildcard *.something
    return if $data->{name} =~ /\.\*\./;   # wildcard some.*.something

    if ( $data->{name} =~ /\*/ ) {
        return $self->error('name',
            "only *.something or * (by itself) is a valid wildcard record"
        );
    }

    $data->{name} =~ m/($invalid_match)/g;  # match ickies
    $self->error('name', "invalid character(s) in record name -- $1");
}

sub _valid_name {
    my ( $self, $data, $zone_text ) = @_;

    return if ! defined $data->{name};  # edit may not include 'name'

    if ( $data->{name} =~ /\.$/ ) {               # ends with .
        if ( $data->{name} !~ /$zone_text\.$/ ) { # ends with zone.com.
            $self->error('name', "absolute host names are NOT allowed. Remove the dot and the host will automatically live within the current zone.");
        }
    }

    if ( $zone_text =~ /(in-addr|ip6)\.arpa[\.]{0,1}$/i ) {
        $self->valid_reverse_label('name', $data->{name} );
    }
    else {
        $self->valid_label('name', $data->{name}, $data->{type} );
    };
}

sub _valid_address {
    my ( $self, $data, $zone_text ) = @_;

    if ( $zone_text =~ /(in-addr|ip6)\.arpa[\.]{0,1}$/i ) {
        $self->valid_reverse_label('address', $data->{address} );
    }
    else {
        $self->valid_label('address', $data->{address} );
    };

    $data->{address} = $data->{address} . ".$zone_text."
        unless $data->{address} =~ /\.$/;
};

sub _valid_address_chars {
    my ( $self, $data, $zone_text ) = @_;

    # any character is valid in TXT records: RFC 1464
    # SPF format is same as TXT record: RFC 4408
    return if $data->{type} =~ /^TXT|SPF$/;

    my $invalid_chars = $self->get_invalid_chars( $data->{type}, 'address', $zone_text );
    if ( $data->{address} =~ m/$invalid_chars/g ) {
        $self->error('address', "invalid character in record address -- $1");
    };
}

sub _is_fully_qualified {
    my ( $self, $data, $zone_text ) = @_;

    if ( $data->{address} !~ /\.$/ ) {    # if it does not end in .
        $self->error('address',
            "Address for $data->{type} must point to a FQDN (with a '.' at the end): RFCs 1035, 2181. You can use the '\@' character to stand for the zone this record belongs to." );
    }
}

sub _valid_rr_type {
    my ( $self, $data ) = @_;

    return if ! $data->{type};  # edit may not change type

    # the get_record_type will match numeric record IDs and convert them to
    # their codes. For validation here, exclude that ability.
    $self->error('type', "Invalid record type $data->{type}" )
        if $data->{type} =~ /^\d+$/;

    # the form is upper case. The following checks catch
    # the correct type, even if user f's with form input
    $data->{type} =~ tr/a-z/A-Z/;

    $self->error('type', "Invalid record type $data->{type}" )
        if ! $self->get_record_type( { type => $data->{type} } );
}

sub _valid_cname {
    my ( $self, $data, $zone_text ) = @_;

# NAME
    my @args = ( $data->{name}, 'CNAME',
        $data->{nt_zone_id}, $data->{nt_zone_record_id} );

    if ($self->record_exists( @args ) ) {
        $self->error( 'name', "multiple CNAME records with the same name are NOT allowed. (use plain old round robin)" );
    };

    foreach my $a ( qw/ A AAAA MX / ) {
        @args[1] = $a;

        if ( $self->record_exists( @args ) ) {
            $self->error( 'name', "record $data->{name} already exists within zone as an Address ($a) record: RFC 1034 & 2181");
        };
    };

# ADDRESS
    $self->_valid_address( $data, $zone_text );
    $self->_valid_address_chars( $data, $zone_text );
}

sub _valid_a {
    my ( $self, $data, $zone_text ) = @_;

# validation plan: name, address

# NAME
    if ( $self->record_exists(
        $data->{name}, 'CNAME', $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
            $self->error( 'name', "record $data->{name} already exists within zone as an Alias (CNAME) record." );
    };

# ADDRESS
    $self->_valid_address_chars( $data, $zone_text );

    Net::IP::ip_is_ipv4( $data->{address} ) or
        $self->error( 'address',
            'Address for A records must be a valid IP address.'
        );

    $self->valid_ip_address( $data->{address} ) or
        $self->error( 'address',
            'Address for A records must be a valid IP address.'
        );
}

sub _valid_aaaa {
    my ( $self, $data, $zone_text ) = @_;

# NAME
    $self->error( 'name',
        "record $data->{name} already exists within zone as an Alias (CNAME) record."
        ) if ( $self->record_exists(
                $data->{name}, 'CNAME',
                $data->{nt_zone_id}, $data->{nt_zone_record_id}
                )
            );

# ADDRESS
    $data->{address} =~ s/ //g;     # strip out any spaces
    if ( ! Net::IP::ip_is_ipv4( $data->{address} ) ) {
        $data->{address} = Net::IP::ip_expand_address($data->{address},6);
    };

    $self->_valid_address_chars( $data, $zone_text );

# TODO: add support for IPv4 transitional IPs: 2001:db8::1.2.3.4
    Net::IP::ip_is_ipv6( $data->{address} )
        or $self->error( 'address',
            'Address for AAAA records must be a valid IPv6 address.'
        );

    $self->valid_ip_address( $data->{address} ) or
        $self->error( 'address',
            'Address for A records must be a valid IP address.'
        );
}

sub _valid_mx {
    my ( $self, $data, $zone_text ) = @_;

# validation plan: name, weight, address

# NAME
    # MX records cannot share a name with a CNAME
    if ($self->record_exists( $data->{name}, 'CNAME',
            $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
        $self->error( 'name', "MX records must not exist as a CNAME: RFCs 1034, 2181" );
    };

# WEIGHT
    # weight must be 16 bit integer
    $self->valid_16bit_int( 'weight', $data->{weight} );

# ADDRESS
    # MX records must not point to a CNAME
    if ($self->record_exists( $data->{address}, 'CNAME',
            $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
        $self->error( 'address', "MX records must not point to a CNAME: RFC 2181" );
    };

    # if MX target is in zone, assure it does not exist as a CNAME
    if ( $data->{address} =~ /(.*)\.$zone_text\.$/ ) {
        if ($self->record_exists( $1, 'CNAME',
                $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
            $self->error( 'address', "MX records must not point to a CNAME: RFC 2181" );
        };
    }
    else {
        # TODO: use Net::DNS to query the target and assure it's not a CNAME
    };

# reject if CNAME = 'mail'
    # MX records must point to absolute hostnames
    $self->_is_fully_qualified( $data, $zone_text );

    $self->error('address',
        "MX address must be a FQDN (not an IP): RFCs 1035, 2181" )
            if $self->valid_ip_address( $data->{address} );

    if ( ! $self->valid_label( 'address', $data->{address} ) ) {
        $self->error('address', "MX address must be a FQDN: RFC 2181");
    };

    $self->_valid_address_chars( $data, $zone_text );
    $self->_valid_address( $data, $zone_text );
}

sub _valid_ns {
    my ( $self, $data, $zone_text ) = @_;

# validation plan: name, address

# NAME
    # _valid_name will check the name label for validity

    # catch redundant NS records. Creating or editing NS Records with 'name'
    # set to 'zone' is disallowed (these records are created automatically
    # at export time). -gws
    if ( $data->{name} eq "$zone_text." ) {
        $self->error( 'name',
            "The NS Records for '$zone_text.' will automatically be created when the Zone is published to a Nameserver."
        );
    }

# ADDRESS
    # NS records must not point to a CNAME
    if ($self->record_exists( $data->{address}, 'CNAME',
            $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
        $self->error( 'address', "NS records must not point to a CNAME: RFC 2181" );
    };

    # NS records must point to absolute hostnames
    $self->_is_fully_qualified( $data, $zone_text );

    $self->error('address',
        "NS address must be a FQDN (not an IP): RFCs 1035, 2181" )
            if $self->valid_ip_address( $data->{address} );

    if ( ! $self->valid_label( 'address', $data->{address} ) ) {
        $self->error('address', "NS address must be a FQDN: RFC 2181");
    };

    $self->_valid_address_chars( $data, $zone_text );
    $self->_valid_address( $data, $zone_text );
}

sub _valid_srv {
    my ( $self, $data, $zone_text ) = @_;

# NAME
    # SRV records allow leading underscore: RFC 2782
# since we allow _ in the valid_name_chars match, we still need to assure
# that _ is only allowed in the leading position

    # get more restrictive pattern
    my $invalid_match = $self->get_invalid_chars( 'SRV', 'address', $zone_text );

    # check each domain label
    foreach my $label ( split /\./, $data->{name} ) {
        if ( substr($label, 0, 1) eq '_' ) {
            my $rest_of_chars = substr($label, 1);
            if ( $rest_of_chars =~ /($invalid_match)/g ) {
                $self->error( 'name', "invalid characters in SRV record: $1" );
            };
        }
        else {
            if ( $label =~ /($invalid_match)/g ) {
                $self->error( 'name', "invalid characters in SRV record: $1" );
            };
        };
    };

# WEIGHT, PRIORITY, PORT
    # weight, priority, and port must all be 16 bit integers
    my %values_to_check = (
        'weight'   => 'Weight',
        'priority' => 'Priority',
        'other'    => 'Port',
    );

    foreach my $check ( keys %values_to_check ) {
        if ( !$self->valid_16bit_int( $check, $data->{$check} ) ) {
            $self->error( $check,
                "$values_to_check{$check} is required to be a 16bit integer, see RFC 2782"
            );
        }
    }

# ADDRESS
    # SRV records must not point to a CNAME
    if ($self->record_exists( $data->{address}, 'CNAME',
            $data->{nt_zone_id}, $data->{nt_zone_record_id} ) ) {
        $self->error( 'address', "CNAME records must not point to a CNAME: RFC 2782" );
    };

    $self->_is_fully_qualified( $data, $zone_text );

    if ( ! $self->valid_label( 'address', $data->{address} ) ) {
        $self->error('address', "SRV address must be a FQDN: RFC 2782");
    };

    if ( $self->valid_ip_address( $data->{address} ) ) {
        $self->error('address', "SRV address must not be an IP: RFC 2782" );
    };

    $self->_valid_address_chars( $data, $zone_text );
    $self->_valid_address( $data, $zone_text );
}

sub _valid_ptr {
    my ( $self, $data, $zone_text) = @_;
    $self->_valid_address( $data, $zone_text );
    $self->_valid_address_chars( $data, $zone_text );
};

sub _valid_naptr {
    my ( $self, $data, $zone_text ) = @_;

    # Preference and Order must be 16 bit integers
    my %values_to_check = (
        'weight'   => 'Order',
        'priority' => 'Preference',
    );

    foreach my $check ( keys %values_to_check ) {
        if ( !$self->valid_16bit_int( $check, $data->{$check} ) ) {
            $self->error( $check,
                "$values_to_check{$check} is required to be a 16bit integer, see RFC 2782"
            );
        }
    }

# TODO: the following fields should be validated:
# http://www.ietf.org/rfc/rfc2915.txt

# Flags Service Regexp Replacement
# IN NAPTR 100  10  ""   ""  "/urn:cid:.+@([^\.]+\.)(.*)$/\2/i"    .
# IN NAPTR 100  50  "s"  "z3950+I2L+I2C"     ""  _z3950._tcp.gatech.edu.
# IN NAPTR 100  50  "s"  "rcds+I2C"          ""  _rcds._udp.gatech.edu.
# IN NAPTR 100  50  "s"  "http+I2L+I2C+I2R"  ""  _http._tcp.gatech.edu.


# ADDRESS
    $self->_is_fully_qualified( $data, $zone_text );
}

sub get_invalid_chars {
    my ( $self, $type, $field, $zone_text ) = @_;

    # valid domain label characters are defined in RFC 1035. Valid hostnames
    # are defined in RFC 952 and RFC 1123
    # (allow hostnames to start with a digit). The strict match
    # is the fall-through (last) return. The exceptions precede it. These
    # regexp strings match all characters except those in their definition.

    # allow : char for AAAA
    # https://www.tnpi.net/support/forums/index.php/topic,990.0.html
    return '[^a-fA-F0-9:]' if $type eq 'AAAA' && $field eq 'address';
    return '[^0-9\.]'      if $type eq 'A'    && $field eq 'address';

    if ( $field eq 'name' ) {
        # allow _ char for SRV, NS (delegated SRV), & TXT (DKIM, DMARC)
        # DKIM: delegated _domainkey in RFC 5016, 5.3
        return '[^a-zA-Z0-9\-\._]' if $type =~ /^(?:SRV|TXT|NS)$/;

        # DNS & BIND, 4.5: Names that are not host names can consist of any
        # printable ASCII character. I feel like this is providing enough rope
        # for users to hang themselves. The code is here, but disabled.
        #return '[^ -~]' if $type !~ /^(?:A|AAAA|MX|LOC|SPF|SSHFP)$/;
    };

    # allow / in reverse zones, for both name & address: RFC 2317
    return '[^a-zA-Z0-9\-\.\/]' if $zone_text =~ /(in-addr|ip6)\.arpa[\.]{0,1}$/i;

    return '[^a-zA-Z0-9\-\.]';  # RFC 1035: a-z, 0-9, and hyphen
};

sub valid_reverse_label {
    my $self = shift;
    my $type = shift or die "invalid type\n";
    my $name = shift;

    $self->error($type, "missing label") if ! defined $name;

    if ( length $name < 1 ) {
        $self->error($type, "A domain label must have at least 1 octets (character): RFC 2181");
    };

    if ( length $name > 255 ) {
        $self->error($type, "A full domain name is limited to 255 octets (characters): RFC 2181");
    };

    my $label_explain = "(the bits of a name between the dots)";
    foreach my $label ( split(/\./, $name) ) {
        if ( length $label > 63 ) {
            $self->error($type, "Max length of a label $label_explain is 63 octets (characters): RFC 2181");
        };

        if ( length $label < 1 ) {
            $self->error($type, "Minimum length of a label $label_explain is 1 octet (character): RFC 2181");
        };

        if ( substr($label, 0,1) eq '-' ) {
            $self->error($type, "Domain labels $label_explain must not begin with a hyphen: RFC 1035");
        };

        if ( substr($label, -1,1) eq '-' ) {
            $self->error($type, "Domain labels $label_explain must not end with a hyphen: RFC 1035");
        };
    };
};


1;

__END__

=head1 SYNOPSIS


=cut

