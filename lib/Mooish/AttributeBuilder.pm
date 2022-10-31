package Mooish::AttributeBuilder;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);
use Scalar::Util qw(blessed);

our @EXPORT = qw(
	field
	param
	option
	extended
);

our %TYPES = (
	field => {
		is => 'ro',
		init_arg => undef,
	},
	param => {
		is => 'ro',
		required => 1,
	},
	option => {
		is => 'ro',
		required => 0,
		predicate => 1,
	},
	extended => {},
);

our $PROTECTED_PREFIX = '';

our %PROTECTED_METHODS = map { $_ => 1 } qw(builder trigger);

our %METHOD_PREFIXES = (
	reader => 'get',
	writer => 'set',
	clearer => 'clear',
	predicate => 'has',
	builder => 'build',
	trigger => 'trigger',
	init_arg => undef,
);

my @shortcuts;
my @builtin_shortcuts = (

	# expand attribute type
	sub {
		my ($name, %args) = @_;
		my $type = delete $args{_type};

		if ($type && $TYPES{$type}) {
			%args = (
				%{$TYPES{$type}},
				%args,
			);
		}

		return %args;
	},

	# merge lazy + default / lazy + builder
	sub {
		my ($name, %args) = @_;

		if ($args{lazy}) {
			my $lazy = $args{lazy};
			$args{lazy} = 1;

			if (ref $lazy eq 'CODE') {
				check_and_set(\%args, $name, default => $lazy);
			}
			else {
				check_and_set(\%args, $name, builder => $lazy);
			}
		}

		return %args;
	},

	# merge coerce + isa
	sub {
		my ($name, %args) = @_;

		if (blessed $args{coerce}) {
			check_and_set(\%args, $name, isa => $args{coerce});
			$args{coerce} = 1;
		}

		return %args;
	},

	# make sure params with defaults are not required
	sub {
		my ($name, %args) = @_;

		if ($args{required} && (exists $args{default} || $args{builder})) {
			delete $args{required};
		}

		return %args;
	},

	# method names from shortcuts
	sub {
		my ($name, %args) = @_;

		# initialized lazily
		my $normalized_name;
		my $protected_field;

		# inflate names from shortcuts
		foreach my $method_type (keys %METHOD_PREFIXES) {
			next unless defined $args{$method_type};
			next if ref $args{$method_type};
			next unless grep { $_ eq $args{$method_type} } '1', -public, -hidden;

			$normalized_name //= get_normalized_name($name, $method_type);
			$protected_field //= $name ne $normalized_name;

			my $is_protected =
				$args{$method_type} eq -hidden
				|| (
					$args{$method_type} eq '1'
					&& ($protected_field || $PROTECTED_METHODS{$method_type})
				);

			$args{$method_type} = join '_', grep { defined }
				($is_protected ? $PROTECTED_PREFIX : undef),
				$METHOD_PREFIXES{$method_type},
				$normalized_name;
		}

		# special treatment for trigger
		if ($args{trigger} && !ref $args{trigger}) {
			my $trigger = $args{trigger};
			$args{trigger} = sub {
				return shift->$trigger(@_);
			};
		}

		return %args;
	},

	# literal parameters (prepended with -)
	sub {
		my ($name, %args) = @_;

		foreach my $literal (keys %args) {
			if ($literal =~ m{\A - (.+) \z}x) {
				$args{$1} = delete $args{$literal};
			}
		}

		return %args;
	},

);

sub field
{
	my ($name, %args) = @_;

	return ($name, expand_shortcuts(field => $name, %args));
}

sub param
{
	my ($name, %args) = @_;

	return ($name, expand_shortcuts(param => $name, %args));
}

sub option
{
	my ($name, %args) = @_;

	return ($name, expand_shortcuts(option => $name, %args));
}

sub extended
{
	my ($name, %args) = @_;

	my $extended_name;
	if (ref $name eq 'ARRAY') {
		$extended_name = [map { "+$_" } @{$name}];
	}
	else {
		$extended_name = "+$name";
	}

	return ($extended_name, expand_shortcuts(extended => $name, %args));
}

sub add_shortcut
{
	my ($sub) = @_;

	croak 'Custom shortcut passed to add_shortcut must be a coderef'
		unless ref $sub eq 'CODE';

	push @shortcuts, $sub;
	return;
}

# Helpers - not part of the interface

sub check_and_set
{
	my ($hash_ref, $name, %pairs) = @_;

	foreach my $key (keys %pairs) {
		croak "Could not expand shortcut: $key already exists for $name"
			if exists $hash_ref->{$key};

		$hash_ref->{$key} = $pairs{$key};
	}

	return;
}

sub get_normalized_name
{
	my ($name, $for) = @_;

	croak "Could not use attribute shortcut with array fields: $for is not supported"
		if ref $name;

	$name =~ s/^_//;
	return $name;
}

sub expand_shortcuts
{
	my ($attribute_type, $name, %args) = @_;

	$args{_type} = $attribute_type;

	# NOTE: builtin shortcuts are executed after custom shortcuts
	foreach my $sub (@shortcuts, @builtin_shortcuts) {
		%args = $sub->($name, %args);
	}

	return %args;
}

1;

# ABSTRACT: build Mooish attribute definitions with less boilerplate

