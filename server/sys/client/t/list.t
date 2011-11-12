##########
##########
# test the NicTool::List class
##########
# (C) 2002 Dajoba LLc
##########

use Test;
BEGIN { plan tests => 41 }

use NicTool;
use NicTool::List;
ok(1);
my $nt = NicTool->new;

#test a list of Results where list param is 'test'
my $list = NicTool::List->new( $nt, 'Result', 'test',
    { 'test' => [ { 'id' => '1' }, { 'id' => '2' }, { 'id' => '3' } ] } );
ok( ref $list, 'NicTool::List' );

#make sure settings are correct
ok( $list->item_type,  'Result' );
ok( $list->type,       'List' );
ok( $list->list_param, 'test' );

#should have 3 objects in list
ok( $list->size, 3 );
ok( $list->more );
$list->next;
$list->next;
$list->next;

#no more
ok( !$list->more );
ok( !$list->next );

#reset
$list->reset;
ok( $list->more );

#make sure items are correct
my $o;
my $i = 1;
while ( $list->more ) {
    $o = $list->next;
    ok( ref $o, 'NicTool::Result' );
    ok( $o->has('id') );
    ok( $o->get('id'), $i );
    $i++;
}
ok( !$list->more );
$list->reset;
ok( $list->more );

#list_as_ref just returns the list as an array ref
ok( ref $list->list_as_ref, 'ARRAY' );
my $arr = $list->list_as_ref;
$i = 1;

#verify array ref is correct
foreach (@$arr) {
    $o = $_;
    ok( ref $o, 'NicTool::Result' );
    ok( $o->has('id') );
    ok( $o->get('id'), $i );
    $i++;
}

#list just returns the list as an array
ok( scalar $list->list, 3 );
my @arr = $list->list;
$i = 1;

#verify array ref is correct
foreach (@arr) {
    $o = $_;
    ok( ref $o, 'NicTool::Result' );
    ok( $o->has('id') );
    ok( $o->get('id'), $i );
    $i++;
}

