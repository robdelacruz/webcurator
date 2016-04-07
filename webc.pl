#!/usr/bin/perl

use strict;
use warnings;
use 5.012;

use DateTime;
use DateTime::Format::ISO8601;
use File::Path;

###
### Helper functions
###
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

sub read_template_file {
	my $template_filename = shift;
	open my $htemplate, '<', $template_filename
		or die "Can't open '$template_filename': $!\n";

	local $/;
	my $template_str = <$htemplate>;
	close $htemplate;
	return $template_str;
}

###
### Templates
###
my $page_article_template = &read_template_file('page_article_template.html');
my $article_template = &read_template_file('article_template.html');
my $page_archives_template = &read_template_file('page_archives_template.html');

###
### Global structures
###
my %articles;
my @sorted_articles_keys;

&main();

### Start here ###
sub main {
	&process_article_files(@ARGV);

	my $output_dir = 'site';

	&clear_outputdir($output_dir);

	print "Writing articles html to $output_dir...\n";
	&write_article_html_files($output_dir);

	print "Writing archives html page to $output_dir...\n";
	&write_archives_html_file($output_dir);
}

# Return whether filename has WEBC signature
sub is_webc_file {
	my ($article_filename) = @_;

	my $harticlefile;
	if (!open $harticlefile, '<', $article_filename) {
		warn "Error opening '$article_filename': $!\n";
		return 0;
	}

	my $first_line = <$harticlefile>;
	return 0 if !$first_line;

	chomp($first_line);
	my $is_webc = 0;
	if ($first_line =~ /^WEBC \d+\.\d+/) {
		$is_webc = 1;
	}

	close $harticlefile;
	return $is_webc;
}

# Return ($datetime, $title_str, $title_filename) from %articles hash key
sub parse_article_key {
	my $article_key = shift;

	my $sep = '___';
	my ($author, $dt_str, $title) = split(/$sep/, $article_key);

	my $dt = datetime_from_str($dt_str);
	my $title_filename = "$title.html";
	$title =~ s/\+/ /g;

	return ($author, $dt, $title, $title_filename);
}

# Parse list of article text files into hash structure
sub process_article_files {
	my @input_files = @_;

	foreach my $article_filename (@input_files) {
		print "Processing file: $article_filename... ";

		if (! -e $article_filename) {
			print "File not found.\n";
			next;
		} elsif (! -r _) {
			print "Can't access file.\n";
			next;
		} elsif (! -T _) {
			print "Invalid file.\n";
			next;
		} elsif (!&is_webc_file($article_filename)) {
			print "Missing WEBC n.n header line.\n";
			next;
		}

		print "\n";

		&process_article_file($article_filename);
	}

	@sorted_articles_keys = sort {
		my ($author_a, $dt_a) = &parse_article_key($a);
		my ($author_b, $dt_b) = &parse_article_key($b);

		my $result_dt = $dt_a <=> $dt_b;
		if ($result_dt == 0) {
			return $author_a <=> $author_b;
		} else {
			return $result_dt;
		}
	} keys %articles;
}

# Parse one article text file and add entry to hash structure
sub process_article_file {
	my ($article_filename) = @_;

	my $harticlefile;
	if (!open $harticlefile, '<', $article_filename) {
		warn "Error opening '$article_filename': $!\n";
		return;
	}

	# Skip WEBC n.n line
	my $first_line = <$harticlefile>;

	# Add each 'HeaderKey: HeaderVal' line to %headers
	my %headers;
	while (my $line = <$harticlefile>) {
		chomp($line);

		last if length($line) == 0;

		my ($k, $v) = split(/:\s*/, $line);
		next if length trim($k) == 0;
		next if !defined $v;
		next if length trim($v) == 0;

		$headers{$k} = $v;
	}

	# Add each article content to %articles under key '<datetime>_<title>'
	my $article_date = $headers{'Date'};
	my $article_title = $headers{'Title'};
	my $article_author = $headers{'Author'};

	if (defined $article_date && defined $article_title && defined $article_author) {
		$article_title =~ s/\s/+/g;

		my $article_dt = datetime_from_str($article_date);
		if ($article_dt) {
			# Add to articles hash.
			my $sep = '___';
			my $article_key =
				$article_author . $sep . $article_dt->datetime() . $sep . $article_title;

			my $article_content;
			{
				local $/;
				$article_content = <$harticlefile>;
			}
			$articles{$article_key} = $article_content;
		} else {
			print "Skipping $article_filename. Invalid header date: '$article_date'\n";
		}
	} else {
		print "Skipping $article_filename. Date, Author, or Title missing in Header.\n";
	}

	close $harticlefile;
}

sub clear_outputdir {
	my $outdir = shift;

	rmtree $outdir;
	mkdir $outdir;
}

sub write_to_file {
	my ($outfilename, $content) = @_;

	open my $houtfile, '>', $outfilename
		or die "Can't write '$outfilename'.";
	print $houtfile $content;
	close $houtfile;
}

sub construct_article_html {
	my ($article_author, $article_dt, $article_title, $article_content) = @_;

	my $article_html = $article_template;

	$article_html =~ s/{title}/$article_title/g;
	$article_html =~ s/{author}/$article_author/g;

	my $dt_formattedstr = $article_dt->year . "/" .
						  $article_dt->month . "/" .
						  $article_dt->day;
	$article_html =~ s/{date}/$dt_formattedstr/g;

	$article_html =~ s/{article_content}/$article_content/g;

	return $article_html;
}

# Given articles hash structure, output the html file list
sub write_article_html_files {
	my $outdir = shift;

	my $prev_k;
	my $next_k;

	for my $i (0..$#sorted_articles_keys) {
		my $k = $sorted_articles_keys[$i];
		$next_k = $sorted_articles_keys[$i+1];

		my ($article_author, $article_dt, $article_title, $article_title_filename)
			= parse_article_key($k);

		if (!$article_dt) {
			print "Can't parse datetime in '$article_title'. Skipping.\n";
			next;
		}

		my $article_html =
			&construct_article_html($article_author, $article_dt, $article_title, $articles{$k});

		my $prev_article_href = '';
		if ($prev_k) {
			my ($author, $prev_dt, $prev_title, $prev_title_filename) = parse_article_key($prev_k);
			$prev_article_href = "Previous: <a href='$prev_title_filename'>$prev_title</a>";
		}
		my $next_article_href = '';
		if ($next_k) {
			my ($author, $next_dt, $next_title, $next_title_filename) = parse_article_key($next_k);
			$next_article_href = "Next: <a href='$next_title_filename'>$next_title</a>";
		}

		my $page_article_html = $page_article_template;
		$page_article_html =~ s/{title}/$article_title/g;
		$page_article_html =~ s/{prev_article_href}/$prev_article_href/g;
		$page_article_html =~ s/{next_article_href}/$next_article_href/g;
		$page_article_html =~ s/{article}/$article_html/g;

		my $outfilename = "$outdir/$article_title_filename";
		print "Writing to file '$outfilename'...\n";
		&write_to_file($outfilename, $page_article_html);

		$prev_k = $k;
	}
}

# Given articles hash structure, output the html file list
sub write_archives_html_file {
	my $outdir = shift;

	my $page_archives_html = $page_archives_template;

	my $archive_content;
	my $year = -1;
	foreach my $k (@sorted_articles_keys) {
		my ($author, $dt, $title, $title_filename) = parse_article_key($k);

		my $yearMarkup;
		if ($year != $dt->year) {
			$yearMarkup = "<h2>" . $dt->year . "</h2>\n";
			$year = $dt->year;
		} else {
			$yearMarkup = "";
		}

		my $article_href = "<a href='$title_filename'>$title</a>\n";

		$archive_content .= $yearMarkup . $article_href;
	}

	$page_archives_html =~ s/{archive_content}/$archive_content/g;

	my $archives_filename = 'archives.html';
	my $outfilename = "$outdir/$archives_filename";
	print "Writing to file '$outfilename'...\n";
	&write_to_file($outfilename, $page_archives_html);
}
