#!/usr/bin/perl
#
use strict;
use warnings;
use 5.012;

my $do_log = 0;

sub logln {
	say @_ if $do_log;
}

sub trim {
	my $str_ref = shift;

	$$str_ref =~ s/^[\s\n]+//s;
	$$str_ref =~ s/[\s\n]+$//s;
}

sub process_template {
	my ($template_str, $data_node) = @_;

	# Process an array loop template:
	# {{@items}}
	# 	<li>{{$.}}</li>
	# {{/@items}}
	#
	# Given a hash %data, it will read $data->{items} to read the array ref that items points to.
	# This will recursively call process_template() for each item in the array passing the item
	# to the template section (<li>...</li>) within the start and end tokens.
	#
	while ($template_str =~ /({{\@([\w\.]+?)}}(.*){{\/\@[\w\.]*?}})/s) {
		my $loop_section = $1;
		my $key = $2;
		my $inner_template = $3;

		$inner_template =~ s/^\n//s;

		my $array_node;
		if ($key eq '.') {
			$array_node = $data_node;
		} else {
			$array_node = $data_node->{$key};
		}

		logln("Loop matched: loop_section:'$loop_section', key:'$key', inner_template:'$inner_template'");

		my $replacement;
		if (defined $array_node && (ref $array_node eq 'ARRAY')) {
			my @inner_replacement_lines;
			foreach my $array_item (@$array_node) {
				my $line = process_template($inner_template, $array_item);
				logln("Output line: $line");
				push @inner_replacement_lines, $line;
			}
			$replacement = join "$/", @inner_replacement_lines;
		}
		if (!defined $replacement) {
			$replacement = "*** undefined \$$key ***";
		}
		$template_str =~ s/\Q$loop_section\E/$replacement/;
	}

	# Process a string token:
	# <h2>{{$item}}</h2>
	#
	# Given a hash %data, it will read $data->{item} to read the scalar ref that item points to.
	# Then replace {{$item}} with the corresponding scalar string.
	#
	my @results;
	foreach my $template_line (split /\n/, $template_str) {
		while ($template_line =~ /({{\$([\w\.]+?)}})/) {
			my $token = $1;
			my $key = $2;

			logln("Matched:$template_line, token:'$token'");

			my $replacement;
			if ($key eq '.') {
				$replacement = $data_node;
			} else {
				$replacement = $data_node->{$key};
			}
			if (!defined $replacement) {
				$replacement = "*** undefined \$$key ***";
			}
			$template_line =~ s/\Q$token\E/$replacement/;
		}
		push @results, $template_line;
	}
	return join "\n", @results;
}

my $template_str1 = q{
	<div>{{$.}}</div><span>{{$.}}</span><h1>{{$.}}</h1>
	<p>{{$.}}</p>
};
my $data1 = 'coffee';
say '{{$.}} test:', process_template($template_str1, $data1);

my $template_str2 = q{
	<h1>{{$title}}</h1>
	<aside>type: {{$type}}</aside>
	<p>{{$content}}</p>
};
my $data2 = {
	title => 'Coffee Title',
	type => 'drink',
	content => "This is the content for the coffee article.\nOn multiple paragraphs.",
};
say '{{$key}} test: ', process_template($template_str2, $data2);

my $template_str3 = q{
	<h2>Drinks List</h2>
	<ul>
{{@.}}
		<!-- Line: {{$.}} -->
		<li>{{$.}}</li>
{{/@.}}
	</ul>
};
my $data3 = ['coffee', 'tea', 'juice'];
say '{{@.}} test: ', process_template($template_str3, $data3);

my $template_str4 = q{
	<h2>{{$title}}</h2>
	<ul class='{{$drink_list_class}}'>
{{@drinks}}
		<li>{{$.}}</li>
{{/@drinks}}
	</ul>
	<footer>{{$footer}}</footer>
};
my $data4 = {
	title => 'Available Drinks',
	footer => 'Generated by Web Curator template.',
	drink_list_class => 'drink-list',
	drinks => ['coffee', 'tea', 'juice'],
};
say 'Hash with array test: ', process_template($template_str4, $data4);

my $template_str5 = q{
	<ul>
{{@.}}
		<li class='{{$class}}'>{{$name}}</li>
{{/@.}}
	</ul>
};
my $data5 = [
	{
		id => 1,
		name => 'coffee',
		class => 'c1',
		caffeine => 'yes',
	},
	{
		id => 2,
		name => 'tea',
		class => 't1',
		caffeine => 'yes',
	},
	{
		id => 3,
		name => 'juice',
		class => 'j1',
		caffeine => 'no',
	},
];
say 'Root array of hashes: ', process_template($template_str5, $data5);

my $template_str6 = q{
	<h1>{{$title}}</h1>
{{@articles}}
	<article>
		<h2>{{$title}}</h2>
		<aside>Author: {{$author1}}</aside>
		<p>{{$content}}</p>
	</article>
{{/@articles}}
	<footer>{{$footer}}</footer>
};
my $data6 = {
	title => 'All Articles',
	footer => 'Generated by Web Curator Template Generator',
	articles => [
		{
			title => 'Lee Kuan Yew',
			author => 'rob',
			date => '2016-04-27',
			content => 'LKY article content goes here...',
		},
		{
			title => 'Web Curator',
			author => 'admin',
			date => '2016-04-27',
			content => 'Web Curator article content goes here...',
		},
		{
			title => 'Coffee',
			author => 'rob',
			date => '2016-04-27',
			content => 'Coffee article content goes here...',
		},
	],
};
say 'Hash of array of hashes: ', process_template($template_str6, $data6);

my $data6_1 = {
};
say 'Hash of array of hashes with nonexisting keys: ', process_template($template_str6, $data6_1);
