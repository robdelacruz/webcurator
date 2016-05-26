#!/usr/bin/perl

use strict;
use warnings;
use 5.012;

use DateTime;
use DateTime::Format::ISO8601;
use File::Path;
use File::Copy qw(copy);
use Text::Markdown qw(markdown);

use File::Basename;
use File::Spec;

BEGIN {
	sub script_dirname {
		return dirname(File::Spec->rel2abs($0));
	}
	use lib script_dirname();
}
use Template;

###
### Global structures
###
my @all_articles;
my %articles_by_title;
my %articles_by_author;

main();

### Start here ###
sub main {
	process_article_files(@ARGV);

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

	foreach my $author (keys %articles_by_author) {
		my $articles_of_author = $articles_by_author{$author};
		my @sorted_articles = sort by_date @$articles_of_author;
		$articles_by_author{$author} = \@sorted_articles;
	}

	my $output_dir = 'site';

	clear_outputdir($output_dir);

	print "Writing articles html to $output_dir...\n";
	write_article_html_files($output_dir);

	print "Writing archives html page to $output_dir...\n";
	write_archives_html_file($output_dir);

	print "Writing title pages html to $output_dir...\n";
	write_title_html_files($output_dir);

	print "Writing author pages html to $output_dir...\n";
	write_author_html_files($output_dir);

	print "Writing index pages to $output_dir...\n";
	write_index_html_files($output_dir);

	copy(File::Spec->catpath('', script_dirname(), 'style.css'), "$output_dir/style.css");
}

###
### Helper functions
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

sub formatted_date {
	my $dt = shift;

	my $dt_formattedstr = $dt->year . "/" .
						  $dt->month . "/" .
						  $dt->day;
	return $dt_formattedstr;
}
### End Helper functions
###


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
		} elsif (!is_webc_file($article_filename)) {
			print "Missing WEBC n.n header line.\n";
			next;
		}

		print "\n";

		process_article_file($article_filename);
	}
}

sub create_article {
	my ($title, $dt, $author, $type, $content) = @_;

	my $article_ref = {
		title => $title,
		dt => $dt,
		formatted_date => formatted_date($dt),
		author => $author,
		type => $type,
		content => $content,
		content_html => markdown($content),
		article_link => filename_link_from_title($title),
		title_link => 'title_' . filename_link_from_title($title),
		author_link => 'author_' . filename_link_from_title($author),
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

			# Add to articles hash.
			my $article_ref = create_article(
				$article_title,
				$article_dt,
				$article_author,
				$article_type // '',
				$article_content
			);
			submit_article($article_ref);
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

sub filename_link_from_title {
	my $item = shift;
	$item =~ s/\s/\+/g;
	return "$item.html";
}

sub process_stock_template_file {
	my ($template_filename, $page_data) = @_;

	my $template_filepath = File::Spec->catpath('', script_dirname(), $template_filename);
	return Template::process_template_file($template_filepath, $page_data);
}

# Generate html files for all articles
sub write_article_html_files {
	my $outdir = shift;

	my $article;
	my $prev_article;
	my $next_article;

	for my $i (0..$#all_articles) {
		$article = $all_articles[$i];
		$next_article = $all_articles[$i+1];

		my $page_data = {
			header => create_header_card_data('Web Curator', 'Curated articles'),
			footer => create_footer_card_data('Generated by Web Curator', ''),
			nav => create_nav_card_data(),
			article => $article,
			prev_article => $prev_article,
			next_article => $next_article,
			recent_articles => create_recent_articles_card_data(),
		};

		my $page_article_html = process_stock_template_file('tpl_page_article.html', $page_data);
		my $article_filename = filename_link_from_title($article->{title});
		my $outfilename = "$outdir/$article_filename";
		print "==> Writing to file '$outfilename'...\n";
		write_to_file($outfilename, $page_article_html);

		$prev_article = $article;
	}
}

# Generate archives html file containing links to all articles
sub write_archives_html_file {
	my $outdir = shift;

	my %articles_of_year;
	foreach my $article (@all_articles) {
		push(@{$articles_of_year{$article->{dt}->year}}, $article);
	}

	# Array of years
	# [
	#	{year: 1970, articles: [list of articles in 1970]},
	#	{year: 1971, articles: [list of articles in 1971]},
	#	...
	# ]
	my @article_links_by_year;
	foreach my $year (sort keys %articles_of_year) {
		my $article_links_data = {
			heading => $year,
			articles => $articles_of_year{$year},
		};
		push @article_links_by_year, $article_links_data;
	}

	my $page_data = {
		header => create_header_card_data('Web Curator', 'Curated articles'),
		footer => create_footer_card_data('Generated by Web Curator', ''),
		nav => create_nav_card_data(),
		article_links_by_year => \@article_links_by_year,
		recent_articles => create_recent_articles_card_data(),
	};

	my $page_archives_html = process_stock_template_file('tpl_page_archives.html', $page_data);
	my $archives_filename = 'archives.html';
	my $outfilename = "$outdir/$archives_filename";
	print "==> Writing to file '$outfilename'...\n";
	write_to_file($outfilename, $page_archives_html);
}

sub write_title_html_files() {
	my $outdir = shift;

	foreach my $title (keys %articles_by_title) {
		my $page_data = {
			header => create_header_card_data('Web Curator', 'Curated articles'),
			footer => create_footer_card_data('Generated by Web Curator', ''),
			nav => create_nav_card_data(),
			title => $title,
			articles => $articles_by_title{$title},
			recent_articles => create_recent_articles_card_data(),
		};

		my $page_title_html = process_stock_template_file('tpl_page_title.html', $page_data);
		my $title_filename = "title_" . filename_link_from_title($title);
		my $outfilename = "$outdir/$title_filename";
		print "==> Writing to file '$outfilename'...\n";
		write_to_file($outfilename, $page_title_html);
	}
}

sub write_author_html_files() {
	my $outdir = shift;

	foreach my $author (keys %articles_by_author) {
		my $page_data = {
			header => create_header_card_data('Web Curator', 'Curated articles'),
			footer => create_footer_card_data('Generated by Web Curator', ''),
			nav => create_nav_card_data(),
			author => $author,
			articles_links_data => {
				articles => $articles_by_author{$author},
			},
			recent_articles => create_recent_articles_card_data(),
		};

		my $page_author_html = process_stock_template_file('tpl_page_author.html', $page_data);
		my $author_filename = "author_" . filename_link_from_title($author);
		my $outfilename = "$outdir/$author_filename";
		print "==> Writing to file '$outfilename'...\n";
		write_to_file($outfilename, $page_author_html);
	}
}

sub create_author_links_card_data {
	my @author_links;
	foreach my $author (sort keys %articles_by_author) {
		my $author_link = {
			author => $author,
			author_link => "author_" . filename_link_from_title($author),
		};
		push @author_links, $author_link;
	}
	return {
		heading => 'Authors',
		authors => \@author_links,
	};
}

sub create_recent_articles_card_data {
	my $max_recent_articles = 5;
	my @recent_articles;
	foreach my $article (reverse @all_articles) {
		push @recent_articles, $article;
		last if (--$max_recent_articles == 0);
	}
	return {
		heading => 'Recent Articles',
		articles => \@recent_articles,
	};
}

sub create_header_card_data {
	my ($header_title, $header_aside) = @_;

	return {
		header_title => $header_title,
		header_aside => $header_aside,
	};
}

sub create_footer_card_data {
	my ($footer_title, $footer_aside) = @_;

	return {
		footer_title => $footer_title,
		footer_aside => $footer_aside,
	};
}

sub create_nav_card_data {
	return [
		{nav_item => 'Home', nav_link => 'index.html'},
		{nav_item => 'Archives', nav_link => 'archives.html'},
	];
}

# Generate archives html file containing links to all articles
sub write_index_html_files {
	my $outdir = shift;

	my %page_data;
	$page_data{header} = create_header_card_data('Web Curator', 'Curated articles');
	$page_data{footer} = create_footer_card_data('Generated by Web Curator', '');
	$page_data{nav} = create_nav_card_data();
	$page_data{author_links} = create_author_links_card_data();
	$page_data{recent_articles} = create_recent_articles_card_data();

	my $page_index_html = process_stock_template_file('tpl_page_index.html', \%page_data);
	my $outfilename = "$outdir/index.html";
	print "==> Writing to file '$outfilename'...\n";
	write_to_file($outfilename, $page_index_html);
}


