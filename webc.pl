#!/usr/bin/perl

use strict;
use warnings;
use 5.012;

use DateTime;
use DateTime::Format::ISO8601;
use File::Path;

sub trim {
	my $s = shift;
	$s =~ s/^\s+|\s+$//g;
	return $s
};

sub datetime_from_str {
	my ($dt_str) = @_;

	my $dt;
	eval {
		$dt = DateTime::Format::ISO8601->parse_datetime($dt_str);
	};
	if ($@) {
		return;
	} else {
		return $dt;
	}
}

sub read_post_template {
	my $template_filename = 'template.html';
	open my $hposttemplate, '<', $template_filename
		or die "Can't open '$template_filename': $!\n";

	local $/;
	my $template_str = <$hposttemplate>;
	return $template_str;
}

my $post_template = &read_post_template;
my %posts;

&main();

### Start here ###
sub main {
	&process_post_files(@ARGV);

	my $output_dir = 'site';
	print "Writing output to $output_dir...\n";
	&write_post_html_files($output_dir);
}

# Return whether filename has WEBC signature
sub is_webc_file {
	my ($post_filename) = @_;

	my $hpostfile;
	if (!open $hpostfile, '<', $post_filename) {
		warn "Error opening '$post_filename': $!\n";
		return 0;
	}

	my $first_line = <$hpostfile>;
	return 0 if !$first_line;

	chomp($first_line);
	my $is_webc = 0;
	if ($first_line =~ /^WEBC \d+\.\d+/) {
		$is_webc = 1;
	}

	close $hpostfile;
	return $is_webc;
}

# Parse list of post text files into hash structure
sub process_post_files {
	my @input_files = @_;

	foreach my $post_filename (@input_files) {
		print "Processing file: $post_filename... ";

		if (! -e $post_filename) {
			print "File not found.\n";
			next;
		} elsif (! -r _) {
			print "Can't access file.\n";
			next;
		} elsif (! -T _) {
			print "Invalid file.\n";
			next;
		} elsif (!&is_webc_file($post_filename)) {
			print "Missing WEBC n.n header line.\n";
			next;
		}

		print "\n";

		&process_post_file($post_filename);
	}

	print "Finishing processing files.\n";
}

# Parse one post text file and add entry to hash structure
sub process_post_file {
	my ($post_filename) = @_;

	my $hpostfile;
	if (!open $hpostfile, '<', $post_filename) {
		warn "Error opening '$post_filename': $!\n";
		return;
	}

	# Skip WEBC n.n line
	my $first_line = <$hpostfile>;

	# Add each 'HeaderKey: HeaderVal' line to %headers
	my %headers;
	while (my $line = <$hpostfile>) {
		chomp($line);

		last if length($line) == 0;

		my ($k, $v) = split(/:\s*/, $line);
		next if length trim($k) == 0;
		next if !defined $v;
		next if length trim($v) == 0;

		$headers{$k} = $v;
	}

	# Add each post body to %posts under key '<datetime>_<title>'
	my $post_date = $headers{'Date'};
	my $post_title = $headers{'Title'};

	if (defined $post_date && defined $post_title) {
		$post_title =~ s/\s/+/g;

		my $post_dt = datetime_from_str($post_date);
		if ($post_dt) {
			# Add to posts hash.
			my $post_key = $post_dt->datetime() . "_" . $post_title;
			my $post_body;
			{
				local $/;
				$post_body = <$hpostfile>;
			}
			$posts{$post_key} = $post_body;
		} else {
			print "Skipping $post_filename. Invalid header date: '$post_date'\n";
		}
	} else {
		print "Skipping $post_filename. Date or Title not defined in header.\n";
	}

	close $hpostfile;
}

# Return ($datetime, $title_str, $title_filename) from %posts hash key
sub parse_postkey {
	my $postkey = shift;
	my ($dt_str, $title) = split(/_/, $postkey);

	my $dt = datetime_from_str($dt_str);
	my $title_filename = "$title.html";
	$title =~ s/\+/ /g;

	return ($dt, $title, $title_filename);
}

# Given posts hash structure, output the html file list
sub write_post_html_files {
	my $outdir = shift;

	rmtree $outdir;
	mkdir $outdir;

	my @sorted_keys = sort {
		print "sorted_keys sort: a=$a, b=$b\n";
		my ($dt_a, , ) = &parse_postkey($a);
		my ($dt_b, , ) = &parse_postkey($b);

		if (!$dt_a || !$dt_b) {
			return 0;
		}
		return $dt_a <=> $dt_b;
	} keys %posts;

	my $prev_k;
	my $next_k;

	for my $i (0..$#sorted_keys) {
		my $k = $sorted_keys[$i];
		$next_k = $sorted_keys[$i+1];

		my ($post_dt, $post_title, $post_title_filename) = parse_postkey($k);

		if (!$post_dt) {
			print "Can't parse datetime in '$post_title'. Skipping.\n";
			next;
		}

		my $outfilename = "$outdir/$post_title_filename";
		open my $houtfile, '>', $outfilename
			or die "Can't write '$outfilename'.";

		my $post_html = $post_template;
		$post_html =~ s/{title}/$post_title/g;

		my $dt_formattedstr = $post_dt->year . "/" . $post_dt->month . "/" . $post_dt->day;
		$post_html =~ s/{date}/$dt_formattedstr/g;

		my $post_body = $posts{$k};
		$post_html =~ s/{post}/$post_body/g;

		my $prev_post_href = '';
		if ($prev_k) {
			my ($prev_dt, $prev_title, $prev_title_filename) = parse_postkey($prev_k);
			$prev_post_href = "Previous: <a href='$prev_title_filename'>$prev_title</a>";
		}
		my $next_post_href = '';
		if ($next_k) {
			my ($next_dt, $next_title, $next_title_filename) = parse_postkey($next_k);
			$next_post_href = "Next: <a href='$next_title_filename'>$next_title</a>";
		}

		$post_html =~ s/{prev_post_href}/$prev_post_href/g;
		$post_html =~ s/{next_post_href}/$next_post_href/g;

		print "Writing to file '$outfilename'...\n";
		print $houtfile $post_html;

		close $houtfile;

		$prev_k = $k;
	}
}

