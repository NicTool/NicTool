package NicTool::Log;

# ABSTRACT: the result of a NicTool log query

use strict;
use NicTool::Result;

our @ISA = 'NicTool::Result';

1;

__END__

=pod

=head1 NAME

NicTool::Log - the result of a NicTool log query

=head1 SYNOPSIS

    my $log = $group->get_global_application_log;
    for my $entry ( @{ $log->get('log') } ) { ... }

=head1 DESCRIPTION

The log calls (get_user_global_log, get_global_application_log,
get_group_zones_log, get_zone_log, get_zone_record_log, ...) return a
B<NicTool::Log>: a L<NicTool::Result> holding the log rows and the paging
totals.

=cut
