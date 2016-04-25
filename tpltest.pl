#!/usr/bin/perl
#
use strict;
use warnings;
use 5.012;

my $do_log = 0;

sub log2 {
	say @_ if $do_log;
}

sub process_template {
	my ($template_str, $data_node) = @_;

	my @results;

	foreach my $template_line (split /\n/, $template_str) {
		while ($template_line =~ /({{(\$)([\w\.]+?)}})/) {
			my $token = $1;
			my $sigil = $2;
			my $key = $3;

			log2("Matched:$template_line, token:'$token', sigil:'$sigil', key:'$key'");

			my $replacement;
			if ($sigil eq '$') {
				if ($key eq '.') {
					$replacement = $$data_node;
				} else {
					$replacement = $data_node->{$key};
				}
			} elsif ($sigil eq '@') {
				my $node;
				if ($key eq '.') {
					$node = @$data_node;
				} else {
					$node = @{$data_node->{$key}};
				}

				# Read all lines until closing {{/@.}} token.
				my @inner_array_lines;


			}

			if ($replacement) {
				$template_line =~ s/\Q$token/$replacement/;
			}
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
say '{{$.}} test:', process_template($template_str1, \$data1);

my $template_str2 = q{
	<h1>{{$title}}</h1>
	<aside>type: ({{$type}})</aside>
	<p>{{$content}}</p>
};
my $data2 = {
	title => 'Coffee Title',
	type => 'drink',
	content => 'This is the content for the coffee article.\nOn multiple paragraphs.',
};
say '{{$key}} test: ', process_template($template_str2, $data2);

my $template_str3 = q{
	<h2>Drinks List</h2>
	<ul>
	{{@.}}
		<li>{{$.}}</li>		
	{{/@.}}
	</ul>
};
my $data3 = ['coffee', 'tea', 'juice'];
say '{{@.}} test: ', process_template($template_str3, \$data3);
