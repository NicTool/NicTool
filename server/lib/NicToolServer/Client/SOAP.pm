package NicToolServer::Client::SOAP;
# ABSTRACT: SOAP implementation for NicToolServer

use strict;

@NicToolServer::Client::SOAP::ISA = qw(NicToolServer::Client);

sub new {
    my ( $class, $data ) = @_;
    my $self = {};
    $self->{'data'}             = $data;
    $self->{'protocol_version'} = $data->{'nt_protocol_version'};
    return bless $self, $class;
}

sub data { $_[0]->{'data'} }

1;

__END__

=head1 SYNOPSIS

=cut
