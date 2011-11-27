##########
# test working of objects
##########

use strict;
use lib 'lib';

use Test;
BEGIN { plan tests => 42 }

use NicTool::NTObject;
ok(1);

#basic test
my $nt = new NicTool::NTObject;
ok( ref $nt, 'NicTool::NTObject' );
ok( !defined $nt->type );
ok( !$nt->has('chump') );

#test setting/getting/hassing
$nt->set( chump => 'something' );
ok( $nt->has('chump') );
ok( $nt->get('chump') eq 'something' );
$nt->set( a => 'b', c => 'd' );
ok( $nt->has('a') );
ok( $nt->has('c') );
ok( $nt->get('a') eq 'b' );
ok( $nt->get('c') eq 'd' );
my @a = $nt->get( 'a', 'c' );
ok( $a[0] => 'b' );
ok( $a[1] => 'd' );

#test initializing
$nt = new NicTool::NTObject( a => 'b', c => 'd' );
ok( ref $nt, 'NicTool::NTObject' );
ok( !defined $nt->type );
ok( $nt->has('a') );
ok( $nt->has('c') );
ok( $nt->get('a') => 'b' );
ok( $nt->get('c') => 'd' );
@a = $nt->get( 'a', 'c' );
ok( $a[0] => 'b' );
ok( $a[1] => 'd' );
$nt = undef;

#test initializing with hash ref
$nt = new NicTool::NTObject( { a => 'b', c => 'd' } );
ok( ref $nt, 'NicTool::NTObject' );
ok( !defined $nt->type );
ok( $nt->has('a') );
ok( $nt->has('c') );
ok( $nt->get('a') => 'b' );
ok( $nt->get('c') => 'd' );
@a = $nt->get( 'a', 'c' );
ok( $a[0] => 'b' );
ok( $a[1] => 'd' );
$nt = undef;

#test array ref value (just being anal)
$nt = new NicTool::NTObject( a => [ 'b', 'c' ] );
ok( ref $nt, 'NicTool::NTObject' );
ok( !defined $nt->type );
ok( $nt->has('a') );
ok( ref $nt->get('a'), 'ARRAY' );
@a = @{ $nt->get('a') };
ok( @a == 2 );
ok( $a[0] => 'b' );
ok( $a[1] => 'c' );
$nt = undef;

#test array ref value with hash ref initializer
$nt = new NicTool::NTObject( { c => [ 'd', 'e' ] } );
ok( ref $nt, 'NicTool::NTObject' );
ok( !defined $nt->type );
ok( $nt->has('c') );
ok( ref $nt->get('c'), 'ARRAY' );
@a = @{ $nt->get('c') };
ok( @a == 2 );
ok( $a[0] => 'd' );
ok( $a[1] => 'e' );
$nt = undef;

