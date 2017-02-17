package NicToolServer::Export::MaraDNS;
# ABSTRACT: exporting DNS data to MaraDNS servers

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Export::Base';
use Params::Validate qw/ :all /;

sub postflight {
    my $self = shift;

    # write out a mararc include
    my $dir = shift || $self->{nte}->get_export_dir or return;
    my $fh = $self->get_export_file( 'mararc_databases.inc', $dir );
    $fh->print(qq[ csv2["$_."] = "$_"\n ]) foreach($self->{nte}->zones_exported);
    $fh->close;
    return 1;
}

sub _zr_generic {
    my ($self, $r, $type, @args) = @_;
    my $args_txt = @args ? ' ' . join(' ', map { $r->{$_} } @args) : '';
    return "$r->{name} +$r->{ttl} $type$args_txt $r->{address} ~\n";
}

sub zr_a        { return _zr_generic(@_, 'A')     }
sub zr_aaaa     { return _zr_generic(@_, 'AAAA')  }
sub zr_cname    { return _zr_generic(@_, 'CNAME') }
sub zr_txt      { return _zr_generic(@_, 'TXT')   }
sub zr_ns       { return _zr_generic(@_, 'NS')    }
sub zr_ptr      { return _zr_generic(@_, 'PTR')   }
sub zr_spf      { return _zr_generic(@_, 'SPF')   }
sub zr_mx       { return _zr_generic(@_, 'MX',  'weight') }
sub zr_srv      { return _zr_generic(@_, 'SRV', 'priority', 'weight') } # TODO "priority" def'd?
sub zr_naptr    { return '' }

sub zr_soa {
    my ($self, $z) = @_;
    # TODO $z->{nsname} or $z->{zone} again?
    return "$z->{zone}. SOA $z->{nsname}. $z->{mailaddr} $z->{serial}|$z->{refresh} $z->{retry} $z->{expire} $z->{minimum} ~\n";
}

sub zr_loc {
    my ($self, $r) = @_;
# TODO:
    return "";
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Export::MaraDNS - exporting DNS data to MaraDNS servers

=head1 VERSION

version 2.33

=head1 AUTHOR

Matthias Bethke

=head1 SEE ALSO

MaraDNS RR formats defined here:
http://www.maradns.org/tutorial/man.csv2.html

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
