# ABSTRACT: basic NicTool API login tests

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


use lib '.';
use lib 't';
use lib 'lib';
use NicToolTest;
use NicTool;
use Test;
BEGIN { plan tests => 7 }

ok(1);

#basic login test
my $user = new NicTool(
    server_host => Config('server_host'),
    server_port => Config('server_port')
);
ok( ref $user, 'NicTool' );

$user->login(
    username => Config('username'),
    password => Config('password')
);
ok( !$user->result->is_error );
ok( $user->nt_user_session );

#logout
$user->logout;
ok( !$user->result->is_error );
ok( !$user->nt_user_session );

$user = undef;
$user = new NicTool(
    server_host => Config('server_host'),
    server_port => Config('server_port')
);

$user->login( username => Config('username'), password => 'WRONG' );
ok( $user->result->is_error );
