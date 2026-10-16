#!/usr/bin/perl
use strict;

use warnings;

require 'nictoolclient.conf';

main();

sub main {
    use CGI::Carp qw( );

    my ( $nt_obj, $q, $user ) = NicToolClient->start_page or return;
    $nt_obj->print_header_with_csrf();
    display( $nt_obj, $q, $user );
}

sub display {
    my ( $nt_obj, $q, $user ) = @_;

    $nt_obj->print_page_start($user);

    my @templates = $nt_obj->zone_record_template_list();

    foreach my $template (@templates) {
        next if ( $template eq "none" );

        my $recs = $nt_obj->zone_record_template(
            {   zone       => 'example.com',
                nt_zone_id => 1,
                template   => $template,
                newip      => '10.0.0.1',
                mailip     => '10.0.0.2',
                debug      => 0,
            }
        );

        show_zone_records( $template, $recs );
    }

    print '<div class="dark_grey_bg fat center">
        <form> <input type="button" value="Close" onClick="window.close()"> </form>
     </div>';

    $nt_obj->parse_template($NicToolClient::end_html_template);
}

sub show_zone_records {
    my ( $template, $recs ) = @_;

    return if ( scalar( @{$recs} ) == 0 );

    print qq[
  <table style="width:100%; border-spacing:1;">
    <tr class="dark_bg"><td colspan="6" class="center">$template</td></tr>];

    for ( my $i = 0; $i < scalar( @{$recs} ); $i++ ) {
        my %zone_record = (
            name     => $recs->[$i]->{'name'},
            type     => $recs->[$i]->{'type'},
            address  => $recs->[$i]->{'address'},
            weight   => $recs->[$i]->{'weight'},
            priority => $recs->[$i]->{'priority'},
            other    => $recs->[$i]->{'other'},
        );

        print qq|
            <tr class="light_grey_bg">
                <td> $recs->[$i]->{'name'}</td>
                <td> $recs->[$i]->{'type'}</td>
                <td> $recs->[$i]->{'address'}</td>
                <td> $recs->[$i]->{'weight'}</td>
                <td> $recs->[$i]->{'priority'}</td>
                <td> $recs->[$i]->{'other'}</td>
            </tr>|;
    }

    print qq{ </table> <br> };
}

