#!/usr/bin/perl

use strict;
use warnings;
use 5.012;

use DateTime;
use DateTime::Format::ISO8601;
use File::Path;
use File::Copy qw(copy);
use Text::Markdown qw(markdown);

use Template;

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

###
### Templates
###
my $page_article_template = Template::read_template_file('page_article_template.html');
my $article_template = Template::read_template_file('article_template.html');
my $page_archives_template = Template::read_template_file('page_archives_template.html');
my $page_title_template = Template::read_template_file('page_title_template.html');
my $page_author_template = Template::read_template_file('page_author_template.html');

###
### Global structures
###
my @all_articles;
my %articles_by_title;
my %articles_by_author;

&main();

### Start here ###
sub main {
	&process_article_files(@ARGV);

	sub by_date {
		$a->{dt} <=> $b->{dt} || 
		$a->{title} cmp $b->{title};
	}

	@all_articles = sort by_date @all_articles;

	foreach my $title (keys %articles_by_title) {
		my $articles_of_title = $articles_by_title{$title};
		my @sorted_articles = sort by_date @$articles_of_title;
		$articles_by_title{$title} = \@sorted_articles;
	}

	foreach my $author(keys %articles_by_author) {
		my $articles_of_author = $articles_by_author{$author};
		my @sorted_articles = sort by_date @$articles_of_author;
		$articles_by_author{$author} = \@sorted_articles;
	}

	my $output_dir = 'site';

	&clear_outputdir($output_dir);

	print "Writing articles html to $output_dir...\n";
	&write_article_html_files($output_dir);

	print "Writing archives html page to $output_dir...\n";
	&write_archives_html_file($output_dir);

	print "Writing title pages html to $output_dir...\n";
	&write_title_html_files($output_dir);

	print "Writing author pages html to $output_dir...\n";
	&write_author_html_files($output_dir);

	copy 'style.css', "$output_dir/style.css";
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
		print "==> Processing file: $article_filename... ";

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

sub submit_article {
	my $article_ref = shift;

	push(@all_articles, $article_ref);

	my $title = $article_ref->{title};
	push(@{$articles_by_title{$title}}, $article_ref);

	my $author = $article_ref->{author};
	push(@{$articles_by_author{$author}}, $article_ref);
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

		my ($k, $v) = split(/:\s*/, $line, 2);
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

#			my @article_content_lines = <$harticlefile>;
#			my $article_content = "<p>\n" . join("</p>\n<p>\n", @article_content_lines) . "</p>\n";

			# Add to articles hash.
			my $article_ref = &create_article(
				$article_title,
				$article_dt,
				$article_author,
				$article_type // '',
				$article_content
			);

			&submit_article($article_ref);
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
	my $article_ref = shift;
	my $article_html = $article_template;

	$article_html =~ s/{title}/$article_ref->{title}/g;

	my $title_link = "title_" . filename_link_from_item($article_ref->{title});
	$article_html =~ s/{title_link}/$title_link/g;

	my $article_link = filename_link_from_item($article_ref->{title});
	$article_html =~ s/{article_link}/$article_link/g;

	$article_html =~ s/{author}/$article_ref->{author}/g;
	my $article_dt = $article_ref->{dt};
	my $dt_formattedstr = $article_dt->year . "/" .
						  $article_dt->month . "/" .
						  $article_dt->day;
	$article_html =~ s/{date}/$dt_formattedstr/g;
	$article_html =~ s/{type}/$article_ref->{type}/g;

	my $content_html = markdown($article_ref->{content});
	$article_html =~ s/{article_content}/$content_html/g;
	return $article_html;
}

sub filename_link_from_item {
	my $item = shift;
	$item =~ s/\s/\+/g;
	return "$item.html";
}

# Generate html files for all articles
sub write_article_html_files {
	my $outdir = shift;

	my $article_ref;
	my $prev_article_ref;
	my $next_article_ref;

	for my $i (0..$#all_articles) {
		$article_ref = $all_articles[$i];
		$next_article_ref = $all_articles[$i+1];

		my $prev_article_href = '';
		if ($prev_article_ref) {
			my $prev_title_filename = filename_link_from_item($prev_article_ref->{title});
			$prev_article_href = "Previous: <a href='$prev_title_filename'>$prev_article_ref->{title}</a>";
		}

		my $next_article_href = '';
		if ($next_article_ref) {
			my $next_title_filename = filename_link_from_item($next_article_ref->{title});
			$next_article_href = "Next: <a href='$next_title_filename'>$next_article_ref->{title}</a>";
		}

		my $article_html = &construct_article_html($article_ref);

		my $page_article_html = $page_article_template;
		$page_article_html =~ s/{title}/$article_ref->{title}/g;
		$page_article_html =~ s/{prev_article_href}/$prev_article_href/g;
		$page_article_html =~ s/{next_article_href}/$next_article_href/g;
		$page_article_html =~ s/{article}/$article_html/g;

		my $article_filename = filename_link_from_item($article_ref->{title});
		my $outfilename = "$outdir/$article_filename";
		print "==> Writing to file '$outfilename'...\n";
		&write_to_file($outfilename, $page_article_html);

		$prev_article_ref = $article_ref;
	}
}

# Generate archives html file containing links to all articles
sub write_archives_html_file {
	my $outdir = shift;

	my $page_archives_html = $page_archives_template;

	my $archive_content;
	my $year = -1;

	foreach my $article_ref (@all_articles) {
		my $dt = $article_ref->{dt};

		my $yearMarkup;
		if ($year != $dt->year) {
			$yearMarkup = "<h2>" . $dt->year . "</h2>\n";
			$year = $dt->year;
		} else {
			$yearMarkup = "";
		}

		my $title_filename = filename_link_from_item($article_ref->{title});
		my $article_href = "<a href='$title_filename'>$article_ref->{title}</a>\n";

		$archive_content .= $yearMarkup . $article_href;
	}

	$page_archives_html =~ s/{archive_content}/$archive_content/g;

	my $archives_filename = 'archives.html';
	my $outfilename = "$outdir/$archives_filename";
	print "==> Writing to file '$outfilename'...\n";
	&write_to_file($outfilename, $page_archives_html);
}

sub write_title_html_files() {
	my $outdir = shift;

	foreach my $title (keys %articles_by_title) {
		my $articles_html;

		foreach my $article_ref (@{$articles_by_title{$title}}) {
			my $article_html = &construct_article_html($article_ref);
			$articles_html .= "\n" . $article_html;
		}

		$articles_html .= "\n";

		my $page_title_html = $page_title_template;
		$page_title_html =~ s/{title}/$title/g;
		$page_title_html =~ s/{articles}/$articles_html/g;

		my $title_filename = "title_" . filename_link_from_item($title);
		my $outfilename = "$outdir/$title_filename";
		print "==> Writing to file '$outfilename'...\n";
		&write_to_file($outfilename, $page_title_html);
	}
}

sub write_author_html_files() {
	my $outdir = shift;

	foreach my $author (keys %articles_by_author) {
		my $articles_html;

		foreach my $article_ref (@{$articles_by_author{$author}}) {
			my $article_html = &construct_article_html($article_ref);
			$articles_html .= "\n" . $article_html;
		}

		$articles_html .= "\n";

		my $page_author_html = $page_author_template;
		$page_author_html =~ s/{author}/$author/g;
		$page_author_html =~ s/{articles}/$articles_html/g;

		my $author_filename = "author_" . filename_link_from_item($author);
		my $outfilename = "$outdir/$author_filename";
		print "==> Writing to file '$outfilename'...\n";
		&write_to_file($outfilename, $page_author_html);
	}
}
