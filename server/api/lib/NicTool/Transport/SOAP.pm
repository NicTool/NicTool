#!/usr/bin/perl
# ABSTRACT: SOAP transport module
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#
###

package NicTool::Transport::SOAP;

use SOAP::Lite;
use Data::Dumper;

our @ISA = 'NicTool::Transport';

sub send_request {
    my $self = shift;
    my $url  = shift;
    my %vars = @_;
    $url .= "/soap";
    my $func = delete $vars{action};
    foreach ( keys %vars ) {
        $vars{$_} = '' unless defined $vars{$_};
    }
    $vars{nt_user_session} = $self->_nt->{nt_user_session}
        if defined $self->_nt->{nt_user_session};
    my $soap = SOAP::Lite->new(

        #location of NicToolServer soap server
        proxy => $url,

        #URI is typically org name followed by module path
        uri => sprintf( '%s://%s/NicToolServer/SOAP',
                        $self->_nt->{transfer_protocol},
                        $self->_nt->{server_host} ),

        #don't die on fault, just return result.
        on_fault => sub { my ( $soap, $res ) = @_; return $res; }
    );
    warn "URI: " . $soap->uri . ", proxy: " . $url . "\n"
        if $self->_nt->{debug_soap_setup};
    warn "Calling soap function \"$func\" with params:\n"
        . Dumper( \%vars ) . "\n"
        if $self->_nt->{debug_soap_request};

    #make soap call and evaluate response.
    my $som = $soap->call( $func => \%vars );

#result should be SOAP::SOM object if success or fault, or scalar for transport error
    if ( !ref $som ) {

        #scalar means transport error
        warn "SOAP result SCALAR: " . Dumper($som) . "\n"
            if $self->_nt->{debug_soap_response};
        return {
            error_code => $soap->transport->code,
            error_msg  => 'SOAP: transport error: ' 
                . $url . ': '
                . $soap->transport->status
        };
    }
    elsif ( $som->isa('SOAP::SOM') && !$som->fault ) {
        warn "SOAP result: " . Dumper( $som->result ) . "\n"
            if $self->_nt->{debug_soap_response};
        warn "function $func = \n params{"
            . Dumper( \%vars ) . "}\n"
            . Dumper( $som->result )
            if $self->_nt->{debug_soap_response};

        return $som->result;
    }
    elsif ( $som->isa('SOAP::SOM') && $som->fault ) {
        warn "SOAP result: " . Dumper( $som->result ) . "\n"
            if $self->_nt->{debug_soap_response};
        return {
            'error_code' => $som->faultcode,
            'error_msg'  => 'SOAP: fault: ' . $som->faultstring
        };
    }
    else {
        warn "SOAP result: Unknown: " . Dumper($som) . "\n"
            if $self->_nt->{debug_soap_response};
        return {
            'error_code' => '??',
            'error_msg'  => 'SOAP: Unknown response type:' . ref $som
        };
    }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Transport::SOAP - SOAP transport module

=head1 VERSION

version 1.02

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
