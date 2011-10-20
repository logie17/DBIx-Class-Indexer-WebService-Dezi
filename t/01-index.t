use Test::More;

use strict;
use warnings;

use lib 't/lib';
use Test::MockModule;

my $dezi = get_dezi_mock();

$dezi->mock( 'index', sub { 
    is ${$_[1]}, '{"doc":{"name":["FooBar"]}}';
    is $_[2], 1;
    is $_[3], 'application/json';
} );

BEGIN {
    use_ok('Test');
}

my $schema = Test->initialize;

my $resultset = $schema->resultset('Person');

my $person0 = $resultset->new({
    name    => 'FooBar',
    age     => 18,
});

$person0->insert;

is 1, 1;

done_testing;

sub get_dezi_mock {
    my $dezi = Test::MockModule->new('Dezi::Client');
    $dezi->mock( 'new', sub { return bless {}, $_[0] } );
    return $dezi;
}

1;
