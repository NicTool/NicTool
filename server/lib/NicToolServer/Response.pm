package NicToolServer::Response;
# ABSTRACT: RPC::XML responces with mod_perl

use strict;
use RPC::XML;

@NicToolServer::Response::ISA = 'NicToolServer';

use mod_perl;
use constant MP2 => $mod_perl::VERSION >= 1.99;

sub respond {
    my ( $self, $data ) = @_;

    my $r      = $self->{Apache};
    my $client = $self->{client};

    if (MP2) {
        $r->content_type('text/xml');     # for mod_perl 2
    }
    else {
        $r->send_http_header('text/xml'); # for mod_perl 1
    }

    print( RPC::XML::response->new($data)->as_string );
}

sub send_error {
    my ( $self, $error ) = @_;

    my $r = $self->{Apache};

    #XML-RPC fault
    if (MP2) {
        $r->content_type('text/xml'); # for mod_perl 2
    }
    else {
        $r->send_http_header('text/xml'); # for mod_perl 1
    }
    $r->print(
        RPC::XML::response->new(
            RPC::XML::fault->new(
                $error->{error_code} => $error->{error_msg}
            )
            )->as_string
    );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicToolServer::Response - RPC::XML responces with mod_perl

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
