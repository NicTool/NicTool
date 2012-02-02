package NicToolServer::Export::MaraDNS;
# ABSTRACT: exporting DNS data to MaraDNS servers

use strict;
use warnings;
use Params::Validate qw/ :all /;
use base 'NicToolServer::Export::Base';

sub postflight {
    my $self = shift;

# TODO: 

    return 1;
}

sub zr_a {
    my ($self, $r) = @_;

# Ahost.example.com.|7200|10.1.2.3
    return "A$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_cname {
    my ($self, $r) = @_;

# Calias.example.org.|3200|realname.example.org.
    return "C$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_mx {
    my ($self, $r) = @_;

# @example.com.|86400|10|mail.example.com.
    return "\@$r->{name}|$r->{ttl}|$r->{weight}|$r->{address}\n";
}

sub zr_txt {
    my ($self, $r) = @_;

# Texample.com.|86400|Example.com: Buy example products online
    return "T$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_ns {
    my ($self, $r) = @_;

# Nexample.com.|86400|ns.example.com.
    return "N$r->{name}.|$r->{ttl}|$r->{address}\n";
}

sub zr_ptr {
    my ($self, $r) = @_;

# P3.2.1.10.in-addr.arpa.|86400|ns.example.com.
    return "P$r->{name}|$r->{ttl}|$r->{address}\n";
}

sub zr_soa {
    my ($self, $z) = @_;

# Sexample.net.|86400|example.net.|hostmaster@example.net.|19771108|7200|3600|604800|1800
    return "S$z->{zone}.|$z->{ttl}|$z->{nsname}|$z->{mailaddr}|$z->{serial}|$z->{refresh}|$z->{retry}|$z->{expire}|$z->{minimum}\n";
}

sub zr_spf {
    my ($self, $r) = @_;

# Uexample.com|3600|40|\\010\\001\\002Kitchen sink data
    return "U$r->{name}|$r->{ttl}|99|$r->{address}\n";
}

sub zr_srv {
    my ($self, $r) = @_;

# srvce.prot.name  ttl  class   rr  pri  weight port target
# I suspect these can be completed by using a method just like in the tinydns
# export. Needs testing...
    return "";
}

sub zr_aaaa {
    my ($self, $r) = @_;

# TODO:
# I suspect these can be completed by using a method just like in the tinydns
# export. Needs testing...
    return "";
}

sub zr_loc {
    my ($self, $r) = @_;
# TODO:
    return "";
}


1;

__END__

MaraDNS RR formats defined here:
http://www.maradns.org/tutorial/man.csv1.html
