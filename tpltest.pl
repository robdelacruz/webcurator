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

sub process_array_tokens {
	my ($template_str, $data_node) = @_;

	# Process an array loop template:
	# {{@items}}
	# 	<li>{{$.}}</li>
	# {{/@items}}
	#
	# Given a hash %data, it will read $data->{items} to read the array ref that
	# items points to.
	#
	# This will recursively call process_template() for each item in the array
	# passing the item to the template section (<li>...</li>) within the
	# start and end tokens.
	#
#	while ($template_str =~ /({{@([\w\.]+?)}}(.*){{\/@\2}})/s) {
	while ($template_str =~ /({{([@+])([\w\.]+?)}}(.*){{\/\2\3}})/s) {
		my $loop_section = $1;
		my $sigil = $2;
		my $key = $3;
		my $inner_template = $4;

		$inner_template =~ s/^\n//s;

		my $inner_node;
		if ($key eq '.') {
			$inner_node = $data_node;
		} else {
			$inner_node = $data_node->{$key};
		}

		logln("Loop matched: loop_section:'$loop_section', key:'$key', inner_template:'$inner_template'");

		my $replacement;
		if ($sigil eq '@' && defined $inner_node && ref $inner_node eq ref []) {
			#
			# Process the inner template lines between {{@key}} and {{/@key}}
			# Duplicate the inner template lines for each item in the array node
			# as specified in key.
			#
			my @inner_replacement_lines;
			foreach my $array_item (@$inner_node) {
				my $line = process_template($inner_template, $array_item);
				logln("Output line: $line");
				push @inner_replacement_lines, $line;
			}
			$replacement = join "$/", @inner_replacement_lines;
		} elsif ($sigil eq '+' && defined $inner_node) {
			# Process the inner template lines between {{+key}} and {{/+key}}
			# Pass it the data referenced by the key.
			$replacement = process_template($inner_template, $inner_node);
		}

		if (!defined $replacement) {
			$replacement = "*** undefined \$$key ***";
		}
		$template_str =~ s/\Q$loop_section\E/$replacement/;
	}

	return $template_str;
}

sub process_line_tokens {
	my ($template_str, $data_node) = @_;

	# Process tokens that can be placed on a single line.
	# Types of tokens that can be processed are:
	# {{$key}}: hash key token
	# {{$.}}: <this> scalar token
	# {{&file.ext}}: External template file
	#
	# Ex 1. Process a string token:
	# <h2>{{$item}}</h2>
	#
	# Given a hash %data, it will read $data->{item} to read the scalar ref that
	# item points to.
	# Then replace {{$item}} with the corresponding scalar string.
	#
	# Ex 2. Process an external template file token:
	# {{&article.html}}
	#
	# Read the template from file 'article.html' and process and embed the template
	# from that file.
	#
	my @results;
	foreach my $template_line (split /\n/, $template_str) {
		#
		# Capture the following:
		# {{$key}}      to get the hash value of key
		# {{$.}}        to get the value of current data node
		# {{&file.ext}} to embed the 'file.ext' template
		# {{&file.ext($key)}} to embed 'file.ext' template passing it the hash value of key
		#
		while ($template_line =~ /({{(\$|&)((?:\w+?|\.)|(?:[\w\.]+?))(?:\((.*)\))?}})/) {
			my $token = $1;
			my $sigil = $2;
			my $cmd = $3;
			my $params = $4;

			logln("Matched:$template_line, token:'$token'");

			my $replacement;

			if ($sigil eq '$') {
				my $key = $cmd;
				if ($key eq '.') {
					$replacement = $data_node;
				} else {
					$replacement = $data_node->{$key};
				}
				if (!defined $replacement) {
					$replacement = "*** undefined $sigil$key ***";
				}
			} elsif ($sigil eq '&') {
				my $data_node_for_template = $data_node;
				if (defined $params) {
					if ($params =~ /^(\$|@)(\w+)/) {
						my $param_sigil = $1;
						my $param_key = $2;
						$data_node_for_template = $data_node->{$param_key};

						# Check if template param is a valid hash key.
						# If not, don't process the template file.
						if (!defined $data_node_for_template) {
							$replacement = "*** undefined $param_sigil$param_key ***";
							$template_line =~ s/\Q$token\E/$replacement/;
							next;
						}
					}
				}
				my $template_filename = $cmd;
				$replacement = process_template_file($template_filename, $data_node_for_template);
			}
			$template_line =~ s/\Q$token\E/$replacement/;
		}
		push @results, $template_line;
	}
	return join "$/", @results;
}

sub process_template {
	my ($template_str, $data_node) = @_;

	$template_str = process_array_tokens($template_str, $data_node);
	$template_str = process_line_tokens($template_str, $data_node);
	return $template_str;
}

sub read_template_file {
	my $template_filename = shift;
	open my $htemplate, '<', $template_filename
		or return undef;

	local $/;
	my $template_str = <$htemplate>;
	close $htemplate;
	return $template_str;
}

sub process_template_file {
	my ($template_filename, $data_node) = @_;

	my $template_str = read_template_file($template_filename);
	if (!defined $template_str) {
		return "*** $template_filename not found ***";
	}
	return process_template($template_str, $data_node);
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
		<aside>Author: {{$author}}</aside>
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

my $data7 = {
	month_names => [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)],
	month_numbers => [qw(1 2 3 4 5 6 7 8 9 10 11 12)],
	month_reports => [
		[qw(1 100 1000)],
		[qw(2 200 2000)],
		[qw(3 300 3000)],
		[qw(4 400 4000)],
		[qw(5 500 5000)],
		[qw(6 600 6000)],
		[qw(7 700 7000)],
		[qw(8 800 8000)],
		[qw(9 900 9000)],
		[qw(10 1000 10000)],
		[qw(11 1100 11000)],
		[qw(12 1200 12000)],
	],
};
my $template_str7 = q{
	<table>
		<thead>
			<tr>
{{@month_names}}
				<td>{{$.}}</td>
{{/@month_names}}
			</tr>
		</thead>
		<tbody>
			<tr>
{{@month_numbers}}
				<td>{{$.}}</td>
{{/@month_numbers}}
			</tr>
			<tr>
{{@month_reports}}
				<td>
{{@.}}
					<span>{{$.}}</span>
{{/@.}}
				</td>
{{/@month_reports}}
			</tr>
		</tbody>
	</table>
};
say 'Template using multiple consecutive and nested arrays: ', process_template($template_str7, $data7);

my $template_str8 = q{
	<h1>{{$title}}</h1>
	<aside>type: {{$type}}</aside>
	{{&tpltest_article.html}}
};
my $data8 = {
	title => 'Coffee Title',
	type => 'drink',
	content => "This is the content for the coffee article.\nOn multiple paragraphs.",
};
say 'Include template in root: ', process_template($template_str8, $data8);

my $template_str6_2 = q{
	<h1>{{$title}}</h1>
{{@articles}}
{{&tpltest_article2.html}}
{{/@articles}}
	<footer>{{$footer}}</footer>
};
say 'Include template in array: ', process_template($template_str6_2, $data6);

my $data9 = {
	title => 'Newspapers',
	seattlepi => {
		title => 'Web Curator',
		author => 'admin',
		date => '2016-04-27',
		content => 'Web Curator article content goes here...',
	},
	footer => 'Generated by Web Curator',
};
my $template_str9 = q{
	<h1>{{$title}}</h1>
	<div>
{{&tpltest_article2.html($seattlepi)}}
	</div>
	<div>
{{&tpltest_article2.html($nytimes)}}
	</div>
	<footer>{{$footer}}</footer>
};
say 'Hash in a hash with include template: ', process_template($template_str9, $data9);

my $data10 = {
	array_with_values => [qw(1 2 3)],
	empty_array => [],
};
my $template_str10 = q{
	<ul>
{{@array_with_values}}
		<li>{{$.}}</li>
{{/@array_with_values}}
	</ul>
	<ul>
{{@empty_array}}
		<li>{{$.}}</li>
{{/@empty_array}}
	</ul>
};
say 'Empty array test: ', process_template($template_str10, $data10);

my $data11 = {
	title => 'Page Title',
	article => {
		title => 'Article Title',
		author => 'rob',
		type => 'article',
		content => 'Article content...',
	},
};
my $template_str11 = q{
	<title>{{$title}}</title>
{{+article}}
	<article>
		<h1>{{$title}}</h1>
		<aside>{{$author}}</aside>
		<p>{{$content}}</p>
	{{+.}}
		<span>{{$type}} by {{$author}}</span>
	{{/+.}}
	</article>
{{/+article}}
};
say 'Traverse to hash key within template: ', process_template($template_str11, $data11);

