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
my %articles_by_date;

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
}

sub create_article {
	my ($title, $dt, $author, $type, $content) = @_;

	my $article_ref = {
		title => $title,
		dt => $dt,
		author => $author,
		type => $type,
		content => $content,
	};

	return $article_ref;
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
	my $article_type = $headers{'Type'};

	if (defined $article_date && defined $article_title && defined $article_author) {
		my $article_dt = datetime_from_str($article_date);
		if ($article_dt) {
			my $article_content;
			{
				local $/;
				$article_content = <$harticlefile>;
			}

			# Add to articles hash.
			my $article_ref = &create_article(
				$article_title,
				$article_dt,
				$article_author,
				$article_type // '',
				$article_content
			);
			$articles_by_date{$article_dt->datetime()} = $article_ref;
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

sub title_to_filename {
	my $title = shift;
	$title =~ s/\s/\+/g;
	return "$title.html";
}

# Given articles hash structure, output the html file list
sub write_article_html_files {
	my $outdir = shift;

	my $prev_k;
	my $next_k;

	my @sorted_articles_keys = sort(keys %articles_by_date);
	for my $i (0..$#sorted_articles_keys) {
		my $k = $sorted_articles_keys[$i];
		$next_k = $sorted_articles_keys[$i+1];

		my $prev_article_href = '';
		if ($prev_k) {
			my $prev_article_ref = $articles_by_date{$prev_k};
			my $prev_title_filename = &title_to_filename($prev_article_ref->{title});
			$prev_article_href = "Previous: <a href='$prev_title_filename'>$prev_article_ref->{title}</a>";
		}

		my $next_article_href = '';
		if ($next_k) {
			my $next_article_ref = $articles_by_date{$next_k};
			my $next_title_filename = &title_to_filename($next_article_ref->{title});
			$next_article_href = "Next: <a href='$next_title_filename'>$next_article_ref->{title}</a>";
		}

		my $article_ref = $articles_by_date{$k};
		my $article_html = &construct_article_html(
			$article_ref->{author},
			$article_ref->{dt},
			$article_ref->{title},
			$article_ref->{content}
		);

		my $page_article_html = $page_article_template;
		$page_article_html =~ s/{title}/$article_ref->{title}/g;
		$page_article_html =~ s/{prev_article_href}/$prev_article_href/g;
		$page_article_html =~ s/{next_article_href}/$next_article_href/g;
		$page_article_html =~ s/{article}/$article_html/g;

		my $article_filename = &title_to_filename($article_ref->{title});
		my $outfilename = "$outdir/$article_filename";
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

	my @sorted_articles_keys = sort(keys %articles_by_date);
	foreach my $k (@sorted_articles_keys) {
		my $article_ref = $articles_by_date{$k};
		my $dt = $article_ref->{dt};

		my $yearMarkup;
		if ($year != $dt->year) {
			$yearMarkup = "<h2>" . $dt->year . "</h2>\n";
			$year = $dt->year;
		} else {
			$yearMarkup = "";
		}

		my $title_filename = &title_to_filename($article_ref->{title});
		my $article_href = "<a href='$title_filename'>$article_ref->{title}</a>\n";

		$archive_content .= $yearMarkup . $article_href;
	}

	$page_archives_html =~ s/{archive_content}/$archive_content/g;

	my $archives_filename = 'archives.html';
	my $outfilename = "$outdir/$archives_filename";
	print "Writing to file '$outfilename'...\n";
	&write_to_file($outfilename, $page_archives_html);
}
