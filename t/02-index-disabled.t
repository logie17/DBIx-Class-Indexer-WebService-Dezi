use lib 't/lib';
use Test::More;
use Test::MockModule;
use Test::Exception;
use strict;
use warnings;

BEGIN {
    use_ok('Test');
}

my $schema = Test->initialize;

my $resultset = $schema->resultset('Disabled');

my $test = $resultset->new({
    name        => 'FooBar',
});
$test->insert;

$resultset->find_or_create({
    name        => 'FooBar',
});

lives_ok { $resultset->search( { name => 'BazBar' } )->count, 1 };

done_testing;

