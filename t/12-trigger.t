use v5.10;
use strict;
use warnings;

use Test::More;
use MooseY::FieldBuilder;

{
	package TestWithTrigger;

	sub new
	{
		return bless {}, shift;
	}

	sub _trigger_param
	{
		return 'triggered!';
	}
}

subtest 'testing trigger' => sub {
	my ($name, %params) = field 'param', trigger => 1;

	ok exists $params{trigger};
	is $params{trigger}->(TestWithTrigger->new), 'triggered!',
		'trigger anon sub ok';
};

done_testing;

