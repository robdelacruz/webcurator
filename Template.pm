package Template;

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

sub process_inner_template_tokens {
	my ($template_str, $data_node) = @_;

	# Process an inner template section.
	# This can be an array loop or an inner data template.

	# Process an array loop template:
	# {{@items}}
	# 	<li>{{$.}}</li>
	# {{/@items}}
	#
	# Given a hash %data, it will read $data->{items} to read the array ref that
	# items points to. Then repeat the <li>..</li> section for each item in the
	# array, recursively calling process_template() passing it the array item and
	# the inner template.
	#
	#
	# Process an inner data template:
	# {{+article}}
	#   <h1>{{$title}}</h1>
	#   <aside>{{$author}}</aside>
	#   <p>{{$content}}</content>
	# {{/+article}}
	#
	# Given a hash %data, it will set the current data node to $data->{article}
	# and pass that node to the inner template within the {{+key}}..{{/+key}} tokens.
	# Then it will call process_template() passing it the new data node and inner
	# template section.
	#
	while ($template_str =~ /(\{\{([@+])([\w\.]+?)}}(.*)\{\{\/\2\3}})/s) {
		my $loop_section = $1;			# the whole section including the start/end tokens
		my $sigil = $2;					# either @ or +
		my $key = $3;					# hash key or .
		my $inner_template = $4;		# the lines within the start/end tokens

		$inner_template =~ s/^\n//s;

		my $inner_node;
		if ($key eq '.') {
			$inner_node = $data_node;
		} else {
			if (ref $data_node eq ref {}) {
				$inner_node = $data_node->{$key};
			} else {
				$inner_node = undef;
			}
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
		} elsif ($sigil eq '+') {
			if (defined $inner_node) {
				# Process the inner template lines between {{+key}} and {{/+key}}
				# Pass it the data referenced by the key.
				$replacement = process_template($inner_template, $inner_node);
			} else {
				# No value in hash key so erase the entire template section.
				$replacement = '';
			}
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
		while ($template_line =~ /(\{\{(\$|&)((?:\w+?|\.)|(?:[\w\.]+?))(?:\((.*)\))?}})/) {
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
				} elsif (ref $data_node eq ref {}) {
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

						if (ref $data_node ne ref {}) {
							$replacement = "*** not a hash $param_sigil$param_key ***";
							$template_line =~ s/\Q$token\E/$replacement/;
							next;
						}
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

	if (defined $data_node) {
		$template_str = process_inner_template_tokens($template_str, $data_node);
		$template_str = process_line_tokens($template_str, $data_node);
	}
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

1;

