package NicTool::Transport;
# ABSTRACT: support class and factory for different Transport types
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

sub new {
    my $pkg = shift;
    my $nt  = shift;
    bless { nt => $nt }, $pkg;
}

sub _nt {
    return $_[0]->{nt};
}

sub get_transport_agent {
    my ( $pkg, $protocol, $nt ) = @_;
    my $dp = uc($protocol);
    $dp =~ s/_//g;
    my $trans;
    eval qq(use NicTool::Transport::$dp);
    if ($@) {
        die
            "Unable to use class NicTool::Transport::$dp for data protocol '$protocol' : $@";
    }
    eval qq( \$trans = NicTool::Transport::$dp->new(\$nt));
    if ($@) {
        die
            "Unable to instantiate class NicTool::Transport::$dp for data protocol '$protocol' : $@";
    }
    return $trans;
}

sub _check_setup {
    my $self    = shift;
    my $message = 'OK';
    $message = "ERROR: server_host not set"
        unless ( $self->_nt->{server_host} );
    $message = "ERROR: server_port not set"
        unless ( $self->_nt->{server_port} );

    return $message;
}

sub _send_request {
    my $self = shift;
    my $msg = $self->_check_setup;

    if ( $msg ne 'OK' ) {
        return { 'error_code' => 'XXX', 'error_msg' => $msg };
    }

    my $url = sprintf( '%s://%s:%d',
                       $self->_nt->{transfer_protocol},
                       $self->_nt->{server_host},
                       $self->_nt->{server_port} );

    #my $func = 'send_'.$self->_nt->{data_protocol}.'_request';
    if ( $self->can('send_request') ) {
        return $self->send_request( $url, @_ );
    }
    else {
        return {
            'error_code' => 501,
            'error_msg'  => 'Data protocol not supported: '
                . $self->_nt->{data_protocol}
        };
    }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

NicTool::Transport - support class and factory for different Transport types

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
