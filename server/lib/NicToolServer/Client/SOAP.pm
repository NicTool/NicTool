package NicToolServer::Client::SOAP;
# ABSTRACT: SOAP implementation for NicToolServer

use strict;

@NicToolServer::Client::SOAP::ISA = 'NicToolServer::Client';

sub new {
    my ( $class, $data ) = @_;
    my $self = {};
    $self->{data}             = $data;
    $self->{protocol_version} = $data->{nt_protocol_version};
    return bless $self, $class;
}

sub data { $_[0]->{data} }

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Client::SOAP - SOAP implementation for NicToolServer

=head1 VERSION

version 2.33

=head1 SYNOPSIS

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
