#!/usr/bin/perl

use v5.14;

use DateTime;
use DateTime::Format::Strptime;
use Cwd;
use Text::Markdown qw(markdown);
use File::Basename;
use File::Spec;
use File::Path;
use File::Copy qw(copy);
use File::Copy::Recursive qw(dircopy);
use Getopt::Long qw(GetOptions);
use Config::Tiny;
use Win32::Autoglob;

BEGIN {
	sub script_dirname {
		return dirname(File::Spec->rel2abs($0));
	}
	use lib script_dirname();
}
use Template;
use WPExporter;

###
### Global structures
###
my @all_articles;
my %articles_by_title;
my %articles_by_author;
my %articles_by_topic;

my $siteconf;

main();

### Start here ###
sub main {
	my $usage_txt = <<"EOT";

Usage - Generate website from input text files:

       ./webc.pl [--imagedir <image directory>]
                 [--assetdir <asset directory>]
                 [--conf <config file>]
                 <input files>
Ex. 
   $0 --imagedir images --conf site.conf *.txt


Usage - Generate input text files from exported wordpress xml file and 
        optionally auto-generate website.

       ./webc.pl --exportwp <wordpress export file> [--autogen]
Ex.
   $0 --exportwp wpsite.wordpress.xml --autogen

EOT

	# Sample command-line:
	# ./webc.pl --imagedir src/images --assetdir src/assets --conf site.conf src/*.txt
	#
	# 1. Copy src/images into site/images directory.
	# 2. Copy src/assets into site/assets directory.
	# 3. Read config settings from site.conf.
	# 4. Process all src/*.txt files and generate html into site/ directory.
	#
	# ./webc.pl --exportwp wpexport.xml --autogen
	#
	# 1. Extract posts from wpexport.xml and generate .txt files into output/ directory.
	# 2. (If --autogen specified) Process output/*.txt files and generate html
	#    into site/ directory.
	#
	my $src_imagedir;
	my $src_assetdir;
	my $conf_file;
	my $wpexport_file;
	my $autogen;
	GetOptions(
		'imagedir=s' => \$src_imagedir,
		'assetdir=s' => \$src_assetdir,
		'conf=s'     => \$conf_file,
		'exportwp=s' => \$wpexport_file,
		'autogen'    => \$autogen,
	) or die $usage_txt;

	if ($wpexport_file) {
		# Generate input text files into output/ dir
		my $output_dir = 'output';
		clear_dir($output_dir);

		# If filename contains a sequence number such as wordpressblog.001.xml,
		# process also wordpressblog.002.xml, wordpressblog.nnn.xml...
		if (my ($base_part, $seq_num) = $wpexport_file =~ /^(.+)\.(\d+)\.xml$/) {
			my $max_seq = '9' x length($seq_num);
			for my $seq_part ($seq_num ... $max_seq) {
				my $cur_export_file = "$base_part.$seq_part.xml";
				last unless -e $cur_export_file;

				WPExporter::export_wp($cur_export_file, $output_dir);
			}
		}
		else {
			# Single export file only
			WPExporter::export_wp($wpexport_file, $output_dir);
		}

		# Generate website from files generated from export_wp(): 
		#   output/*.txt, output/images, output/site.conf
		if ($autogen) {
			my @article_files = glob('output/*.txt');
			generate_site(\@article_files, 'output/site.conf', 'output/images', undef);
		}
	} else {
		if (@ARGV == 0) {
			print $usage_txt;
			exit 0;
		}

		generate_site(\@ARGV, $conf_file, $src_imagedir, $src_assetdir);
	}
}

sub generate_site {
	my ($article_files, $conf_file, $src_imagedir, $src_assetdir) = @_;

	if (@$article_files == 0) {
		return;
	}

	$src_imagedir = $src_imagedir // 'images';
	$conf_file = $conf_file // 'site.conf';

	my $output_dir = 'site';
	clear_dir($output_dir);

	# Copy image, assets source directories and any source files needed to output dir.
	copy_dir($src_imagedir, "$output_dir/images");
	copy_dir($src_assetdir, "$output_dir/assets");
	copy_file('style.css', "$output_dir/style.css");

	# Read settings from site config file
	if (-e $conf_file) {
		$siteconf = Config::Tiny->read($conf_file);
	} else {
		print "'$conf_file' not found. Using default settings.\n";
		$siteconf = Config::Tiny->new();
	}
	fill_in_siteconf_defaults($siteconf);

	process_article_files(@$article_files);

	sort_article_data();

	print "Writing articles html to $output_dir...\n";
	write_article_html_files($output_dir);

	print "Writing author pages html to $output_dir...\n";
	write_author_html_files($output_dir);

	print "Writing archives html page to $output_dir...\n";
	write_archives_html_file($output_dir);

	print "Writing articles toc html page to $output_dir...\n";
	write_articles_toc_html_file($output_dir);

	print "Writing index pages to $output_dir...\n";
	write_index_html_files($output_dir);
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

	state $strptime_std = DateTime::Format::Strptime->new(
		pattern => '%Y-%m-%d %H:%M',
	);
	state $strptime_iso = DateTime::Format::Strptime->new(
			pattern => '%Y-%m-%dT%H:%M',
	);
	state $strptime_dateonly = DateTime::Format::Strptime->new(
			pattern => '%Y-%m-%d',
	);

	my $dt = $strptime_std->parse_datetime($dt_str);
	if (!$dt) {
		$dt = $strptime_iso->parse_datetime($dt_str);
	}
	if (!$dt) {
		$dt = $strptime_dateonly->parse_datetime($dt_str);
	};
	return $dt;
}

sub formatted_date {
	my $dt = shift;

	return DateTime::Format::Strptime::strftime('%e %b %Y', $dt);
}

sub copy_dir {
	my ($src_dir, $target_dir) = @_;

	if ($src_dir) {
		if (-d $src_dir) {
			my ($n1, $num_dirs, $n3) = dircopy($src_dir, $target_dir);
			if ($num_dirs > 0) {
				print "Copied directory '$src_dir' to $target_dir.\n";
			} else {
				print "Error copying '$src_dir'.\n";
			}
		}
	}
}

sub copy_file {
	my ($src_file, $target_file) = @_;
	copy(File::Spec->catpath('', script_dirname(), $src_file), $target_file);
}
### End Helper functions
###

# Set defaults to site config settings that weren't defined
# Default setting will be used when either:
#   - entry doesn't exist
#	- entry defined as blank, as in "site_title="
sub fill_in_siteconf_defaults {
	my $conf = shift;

	# [site]
	$conf->{site} = $conf->{site} // {};
	
	if (!$conf->{site}{site_title}) {
		$conf->{site}{site_title} = 'Web Curator Site';
	}
	if (!$conf->{site}{site_teaser}) {
		$conf->{site}{site_teaser} = 'Generated by Web Curator'
	}
	if (!$conf->{site}{site_footer}) {
		$conf->{site}{site_footer} = 'Site generated by Web Curator';
	}
	if (!$conf->{site}{site_footer_aside}) {
		$conf->{site}{site_footer_aside} = 
			'<a href="https://github.com/robdelacruz/webcurator">https://github.com/robdelacruz/webcurator</a>';
	}
	if (!$conf->{site}{articles_page_heading}) {
		$conf->{site}{articles_page_heading} = 'Articles Contents';
	}
	if (!$conf->{site}{archives_page_heading}) {
		$conf->{site}{archives_page_heading} = 'Archives';
	}
	
	# [articles]
	$conf->{articles} = $conf->{articles} // {};

	if (!$conf->{articles}{topic_order}) {
		$conf->{articles}{topic_order} = '';
	}
	if (!$conf->{articles}{article_show_date}) {
		$conf->{articles}{article_show_date} = 'y';
	}
	if (!$conf->{articles}{article_show_author}) {
		$conf->{articles}{article_show_author} = 'y';
	}
	if (!$conf->{articles}{article_show_topic_link}) {
		$conf->{articles}{article_show_topic_link} = 'n';
	}
}

# Sort global data structures
sub sort_article_data {
	sub by_date {
		$a->{dt} <=> $b->{dt} || 
		$a->{title} cmp $b->{title};
	}
	sub by_seq_date {
		$a->{seq} <=> $b->{seq} ||
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

	foreach my $topic (keys %articles_by_topic) {
		my $articles_of_topic = $articles_by_topic{$topic};
		my @sorted_articles = sort by_seq_date @$articles_of_topic;
		$articles_by_topic{$topic} = \@sorted_articles;
	}
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
		} elsif (!is_webc_file($article_filename)) {
			print "Missing WEBC n.n header line.\n";
			next;
		}

		print "\n";

		process_article_file($article_filename);
	}
}

sub create_article {
	my ($title, $dt, $author, $type, $format, $topics, $seq, $content) = @_;

	# If title already exists, suffix it with a sequence number.
	# Ex. Title 'Blog Entry' becomes 'Blog Entry1'... 'Blog Entry2', etc.
	my $article_unique_title = $title;
	if (exists $articles_by_title{$title}) {
		my $articles_same_title = $articles_by_title{$title};
		my $num_articles_same_title = @{$articles_same_title};
		$article_unique_title .= $num_articles_same_title;
	}

	my $article_ref = {
		title => $title,
		dt => $dt,
		formatted_date => formatted_date($dt),
		author => $author,
		type => $type,
		format => $format,
		topics => $topics,
		seq => $seq,
		content => $content,
		content_html => $format eq 'html'? $content : markdown($content),
		article_link => filename_link_from_title($article_unique_title),
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

	foreach my $topic (@{$article_ref->{topics}}) {
		push(@{$articles_by_topic{$topic}}, $article_ref);
	}
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
	my $article_format = $headers{'Format'};
	my @article_topics = split(/\s*,\s*/, $headers{'Topic'} // '');
	my $article_seq = $headers{'Sequence'};

	if (!@article_topics) {
		push @article_topics, 'Uncategorized';
	}

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
				$article_format // '',
				\@article_topics,
				$article_seq // 99999,
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

sub clear_dir {
	my $dir = shift;

	rmtree $dir;
	mkdir $dir;
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
	$item =~ s/[\s]/+/g;		# whitespace replaced with '+'
	$item =~ s/[^\w\+\-]/_/g;	# punctuation and misc chars replaced with '_'
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
			header => create_header_card_data(),
			footer => create_footer_card_data(),
			nav => create_nav_card_data(),
			article => $article,
			prev_article => $prev_article,
			next_article => $next_article,
			recent_articles => create_recent_articles_card_data(),
		};

		my $page_article_html = process_stock_template_file('tpl_page_article.html', $page_data);
		my $article_filename = $article->{article_link};
		my $outfilename = "$outdir/$article_filename";
		print "==> Writing to file '$outfilename'...\n";
		write_to_file($outfilename, $page_article_html);

		$prev_article = $article;
	}
}

sub create_article_links_by_year_data {
	my $articles = shift;

	my %articles_of_year;
	foreach my $article (@$articles) {
		push(@{$articles_of_year{$article->{dt}->year}}, $article);
	}

	# [
	#	{heading: 1970, articles: [list of articles in 1970]},
	#	{heading: 1971, articles: [list of articles in 1971]},
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

	return \@article_links_by_year;
}

# Generate archives html file containing links to all articles
sub write_archives_html_file {
	my $outdir = shift;

	my $page_data = {
		header => create_header_card_data(),
		footer => create_footer_card_data(),
		page_title => $siteconf->{site}{archives_page_heading},
		nav => create_nav_card_data(),
		article_links_by_year => create_article_links_by_year_data(\@all_articles),
		recent_articles => create_recent_articles_card_data(),
	};

	my $page_archives_html = process_stock_template_file('tpl_page_archives.html', $page_data);
	my $archives_filename = 'archives.html';
	my $outfilename = "$outdir/$archives_filename";
	print "==> Writing to file '$outfilename'...\n";
	write_to_file($outfilename, $page_archives_html);
}

sub write_author_html_files() {
	my $outdir = shift;

	foreach my $author (keys %articles_by_author) {
		my $page_data = {
			header => create_header_card_data(),
			footer => create_footer_card_data(),
			nav => create_nav_card_data(),
			author => $author,
			article_links_by_year =>
				create_article_links_by_year_data($articles_by_author{$author}),
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
	my $max_recent_articles = 10;
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
	return {
		header_title => $siteconf->{site}{site_title},
		header_aside => $siteconf->{site}{site_teaser},
	};
}

sub create_footer_card_data {
	return {
		footer_title => $siteconf->{site}{site_footer},
		footer_aside => $siteconf->{site}{site_footer_aside},
	};
}

sub create_nav_card_data {
	return [
		{nav_item => 'Home', nav_link => 'index.html'},
		{nav_item => 'Articles', nav_link => 'articles.html'},
		{nav_item => 'Archives', nav_link => 'archives.html'},
	];
}

# Generate archives html file containing links to all articles
sub write_index_html_files {
	my $outdir = shift;

	my $page_data = {
		header => create_header_card_data(),
		footer => create_footer_card_data(),
		nav => create_nav_card_data(),
		author_links => create_author_links_card_data(),
		recent_articles => create_recent_articles_card_data(),
	};

	my $page_index_html = process_stock_template_file('tpl_page_index.html', $page_data);
	my $outfilename = "$outdir/index.html";
	print "==> Writing to file '$outfilename'...\n";
	write_to_file($outfilename, $page_index_html);
}

# Generate articles table of contents html file
sub write_articles_toc_html_file {
	my $outdir = shift;

	my @article_links_by_topic;
	my @ordered_topics;
	if ($siteconf->{articles}{topic_order} eq '') {
		@ordered_topics = sort keys %articles_by_topic;
	} else {
		# Arrange topics in order of siteconf topic_order preference
		# Use existing topics in topic_order first, then for the remaining unspecified
		# topics, add them at the end in alphabetic order

		# Get all topics listed in topic_order
		@ordered_topics = split(/\s*,\s*/, $siteconf->{articles}{topic_order});

		# Filter out topics without any posts
		@ordered_topics = grep {exists $articles_by_topic{$_}} @ordered_topics;

		# Add the remaining topics, arranged in alphabetical order
		my %already_added_topics = map {$_ => 1} @ordered_topics;
		foreach my $topic (sort keys %articles_by_topic) {
			if (!exists $already_added_topics{$topic}) {
				push @ordered_topics, $topic;
			}
		}
	}

	foreach my $topic (@ordered_topics) {
		my $article_links_data = {
			heading => $topic,
			articles => $articles_by_topic{$topic},
		};
		push @article_links_by_topic, $article_links_data;
	}

	my $page_data = {
		header => create_header_card_data(),
		footer => create_footer_card_data(),
		page_title => $siteconf->{site}{articles_page_heading},
		nav => create_nav_card_data(),
		article_links_by_topic => \@article_links_by_topic,
		recent_articles => create_recent_articles_card_data(),
	};

	my $articles_toc_html = process_stock_template_file('tpl_page_articles_toc.html', $page_data);
	my $articles_toc_filename = 'articles.html';
	my $outfilename = "$outdir/$articles_toc_filename";
	print "==> Writing to file '$outfilename'...\n";
	write_to_file($outfilename, $articles_toc_html);
}

