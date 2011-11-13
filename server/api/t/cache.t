##########
# test cache mechanism
##########

use Test;
BEGIN { plan tests => 8 }

use NicTool::Cache;
ok(1);

my $c     = new NicTool::Cache;
my $itema = bless { item => 'a' }, 'ITEMA';
my $itemb = bless { item => 'b' }, 'ITEMB';
$c->add( $itema, 'items' => 'a' );
ok( $c->get( 'items' => 'a' ), $itema );
my $i = $c->get( 'items' => 'a' );
ok( $i->{'item'} => 'a' );

$c->add( $itemb, 'items' => 'stuff' => 'b' );
ok( $c->get( 'items' => 'stuff' => 'b' ), $itemb );
$i = $c->get( 'items' => 'stuff' => 'b' );
ok( $i->{'item'} => 'b' );

$c->del( 'items' => 'a' );
ok( $c->get( 'items' => 'a' ) => undef );

$c->del( 'items' => 'stuff' => 'b' );
ok( $c->get( 'items' => 'stuff' => 'b' ) => undef );

$c->add( $itema, 'items' => undef );
ok( $c->get( 'items' => undef ) => undef );
