package WPExporter;

use v5.14;

use XML::Tiny;
use File::Path;

use HTTP::Tiny;
my $tiny = HTTP::Tiny->new();

my $_do_log = 0;

sub find_child_node {
	my ($start_parm, $element_name) = @_;

	my $content_nodes;
	if (ref $start_parm eq ref []) {
		$content_nodes = $start_parm;
	} else {
		$content_nodes = $start_parm->{content};
	}

	my $found_node;
	foreach my $child_node (@$content_nodes) {
		printf("Traversing node name '%s'...\n", $child_node->{name}) if $_do_log;
		if (($child_node->{type} eq 'e') && ($child_node->{name} eq $element_name)) {
			$found_node = $child_node;
			last;
		}
	}

	return $found_node;
}

# Return whether node matches all the specified attribute filters
# Ex.
#   match_attribute_filter($node, {
#   	attrib1 => 'val1',
#   	attrib2 => 'val2',
#   })
#
#   matches <tag1 attrib1='val1' attrib2='val2'>
#
sub match_attribute_filter {
	my ($node, $attribute_filter) = @_;

	if (!$attribute_filter) {
		return 1;
	}
	foreach my $match_attrib_name (keys %$attribute_filter) {
		my $match_attrib_val = $attribute_filter->{$match_attrib_name};
		if (!exists $node->{attrib}{$match_attrib_name}) {
			return 0;
		}
		if ($node->{attrib}{$match_attrib_name} ne $match_attrib_val) {
			return 0;
		}
	}
	return 1;
}

# Ex. find_multiple_child_nodes($node, 'category', {domain => 'post_tag'})
#     to return all child nodes <category domain="post_tag" ...>
#     Set $attribute_filter to undef to not filter by attribute.
sub find_multiple_child_nodes {
	my ($start_parm, $element_name, $attribute_filter) = @_;

	my $content_nodes;
	if (ref $start_parm eq ref []) {
		$content_nodes = $start_parm;
	} else {
		$content_nodes = $start_parm->{content};
	}

	my @found_nodes;
	foreach my $child_node (@$content_nodes) {
		printf("Traversing node name '%s'...\n", $child_node->{name}) if $_do_log;
		if (($child_node->{type} eq 'e') &&
			($child_node->{name} eq $element_name) && 
			match_attribute_filter($child_node, $attribute_filter)
		) {
			push @found_nodes, $child_node;
		}
	}

	return @found_nodes;
}

sub node_text {
	my $node = shift;

	if (!exists $node->{type}) {
		return '';
	}

	if ($node->{type} eq 't') {
		return $node->{content};
	} elsif ($node->{type} eq 'e') {
		foreach my $child_node (@{$node->{content}}) {
			if ($child_node->{type} eq 't') {
				return $child_node->{content};
			}
		}
	}

	return '';
}

# Return hash containing item fields
# Currently returns:
# {
# 	status => 'publish'|'draft'|...
#	post_type => 'post'|'page'|'attachment'|...
# }
sub item_node_info {
	my $item_node = shift;

	my $status = node_text(find_child_node($item_node, 'wp:status'));
	my $post_type = node_text(find_child_node($item_node, 'wp:post_type'));

	return {
		status => $status,
		post_type => $post_type,
	};
}

sub csv_text_from_nodes {
	my $nodes = shift;

	my @categories_texts;
	foreach my $category_node (@$nodes) {
		my $cat = node_text($category_node);
		push @categories_texts, $cat;
	}
	my $categories = join(', ', @categories_texts);
}

sub clear_dir {
	my $dir = shift;

	rmtree $dir;
	mkdir $dir;
}

sub save_image {
	my ($old_image_url, $images_dir, $image_filename) = @_;

	print "Downloading image file '$old_image_url' to '$images_dir/$image_filename'...";
	my $resp = $tiny->get($old_image_url);

	if ($resp->{success}) {
		open my $houtfile, '>', "$images_dir/$image_filename";
		binmode($houtfile);
		print $houtfile scalar $resp->{content};
		close $houtfile;
		print "Done.\n";
	} else {
		print "Error downloading.\n";
	}
}

sub replace_image_urls {
	my ($content, $output_dir) = @_;

	my $images_rel_dir = 'images';
	my $images_dir = "$output_dir/$images_rel_dir";
	unless (-d $images_dir) {
		mkdir $images_dir;
	}

	# Match this:
	# "https://<wp_id>.files.wordpress.com/nnn/nn/.../<image filename>?p=nnn" 
	# Then replace the whole link with [images/<image filename>]
	while ($content =~ /\"(https?:\/\/\w+?\.files\.wordpress\.com\/[\w\/]+\/(\S+\.\w+).*?)\"/) {
		my $old_image_url = $1;
		my $image_filename = $2;
		my $new_image_url = "$images_rel_dir/$image_filename";
		$content =~ s/\Q$old_image_url\E/$new_image_url/g;

		# Save $old_image_url linked file to $images_dir/<image filename>
		save_image($old_image_url, $images_dir, $image_filename);
	}

	return $content;
}

sub replace_shortcodes {
	my $content = shift;

	# Remove caption shortcode and place extracted caption under image.
	# Caption shortcode reference: https://codex.wordpress.org/Caption_Shortcode
	# [caption id="" ...]<img ... /> (Caption goes here) [/caption]
	$content =~ s/\[caption\s+.*?\]\s*(<img.*?\/>)\s*(.*?)\s*\[\/caption\]/<figure>\1<figcaption>\2<\/figcaption><\/figure>/;

	# Strip out youtube shortcode and make youtube url a link
	$content =~ s/\[youtube\s+(\S+)\s+\]/<a href="\1">\1<\/a>/g;

	return $content;
}

sub replace_special_chars {
	my $s = shift;

	$s =~ s/[\s]/+/g;		# whitespace replaced with '+'
	$s =~ s/[^\w\+\-]/_/g;	# punctuation and misc chars replaced with '_'
	return $s;
}

sub write_post_file {
	my ($output_dir, $title, $author, $dt, $excerpt, $categories, $tags, $content) = @_;

	state %num_posts_of_title;

	my $title_in_filename = replace_special_chars($title);

	# Append a sequence number to title if one or more already exists.
	# Ex. If there are two posts with same title "Bee", first one gets
	# "Bee" title, the next one gets "Bee1", next gets "Bee2", etc.
	$num_posts_of_title{$title}++;
	my $num_posts_having_title = $num_posts_of_title{$title};
	if ($num_posts_having_title > 1) {
		$title_in_filename .= $num_posts_having_title;
	}

	my $outfilename = "$output_dir/$title_in_filename.txt";
	print "==> Writing to file '$outfilename'...\n";

	open my $houtfile, '>', $outfilename
		or die "Can't write '$outfilename'.";
	print $houtfile "WEBC 1.0\n";
	print $houtfile "Title: $title\n";
	print $houtfile "Date: $dt\n";
	print $houtfile "Author: $author\n";
	print $houtfile "Type: post\n";
	print $houtfile "Format: markdown\n";
	print $houtfile "Topic: $categories\n";
	print $houtfile "Tags: $tags\n";
	print $houtfile "\n";
	print $houtfile $content;

	close $houtfile;
}

sub generate_config_file {
	my ($output_dir, $conf_filename, $blog_title, $blog_description, $categories) = @_;

	my $categories_csv = join ', ', @$categories;

	# Generates:
	#
	# [site]
	# site_title=<title>
	# site_teaser=<desc>
	# ...
	# [articles]
	# topic_order=
	# article_show_date=y
	# ...

	my $conf_text = <<"EOT";
[site]
site_title=$blog_title
site_teaser=$blog_description
site_footer=
site_footer_aside=
articles_page_heading=Articles Contents
archives_page_heading=Archives

[articles]
topic_order=$categories_csv
article_show_date=
article_show_author=
article_show_topic_link=

EOT

	open my $houtfile, '>', "$output_dir/$conf_filename";
	print $houtfile $conf_text;
	close $houtfile;
}

sub export_single_wpfile {
	my ($wp_export_filename, $output_dir, $skipimages, $export_info) = @_;

	unless (-e $wp_export_filename) {
		print "Can't open '$wp_export_filename'.\n";
		return;
	}

	print "Processing $wp_export_filename...\n";

	my $doc = eval {XML::Tiny::parsefile($wp_export_filename)};
	return unless $doc;

	my $rss_node = find_child_node($doc, 'rss');
	die if !defined $rss_node;
	my $channel_node = find_child_node($rss_node, 'channel');
	die if !defined $channel_node;

	$export_info->{blog_title} = node_text(find_child_node($channel_node, 'title'));
	$export_info->{blog_description} = node_text(find_child_node($channel_node, 'description'));

	my $channel_child_nodes = $channel_node->{content};

	# Get only published posts or pages
	# <item>
	# 	...
	# 	<wp:status>publish</wp:status>
	# 	<wp:post_type>post|page</wp:post_type>
	# 	...
	# </item>
	my @item_nodes;
	foreach (@$channel_child_nodes) {
		my $item_node_info = item_node_info($_);
		if ($_->{type} eq 'e'
			&& $_->{name} eq 'item'
			&& $item_node_info->{status} eq 'publish' 
			&& ($item_node_info->{post_type} eq 'post' || $item_node_info->{post_type} eq 'page')
		) {
			push @item_nodes, $_;
		}
	}
	die "No posts available.\n" if @item_nodes == 0;

	print "Writing output post files to $output_dir...\n";

	foreach my $item_node (@item_nodes) {
		my $title_node = find_child_node($item_node, 'title');
		my $creator_node = find_child_node($item_node, 'dc:creator');
		my $postdate_node = find_child_node($item_node, 'wp:post_date');
		my $excerpt_node = find_child_node($item_node, 'excerpt:encoded');
		my @category_nodes = find_multiple_child_nodes($item_node, 'category', {domain => 'category'});
		my @tag_nodes = find_multiple_child_nodes($item_node, 'category', {domain => 'post_tag'});
		my $content_node = find_child_node($item_node, 'content:encoded');

		my $title = node_text($title_node);
		my $author = node_text($creator_node);
		my $dt = node_text($postdate_node);
		my $excerpt = node_text($excerpt_node);
		my $content = node_text($content_node);
		my $categories = csv_text_from_nodes(\@category_nodes);
		my $tags = csv_text_from_nodes(\@tag_nodes);

		foreach my $category_node (@category_nodes) {
			$export_info->{categories}{node_text($category_node)}++;
		}

		$content = replace_image_urls($content, $output_dir) unless $skipimages;
		$content = replace_shortcodes($content);

		if (length $title > 0 && length $author > 0 && length $content > 0) {
			write_post_file($output_dir, $title, $author, $dt, $excerpt,
								$categories, $tags, $content);
		}
	}
}

sub export_wp {
	my ($wp_export_filename, $output_dir, $skipimages) = @_;

	clear_dir($output_dir);

	# If filename contains a sequence number such as wordpressblog.001.xml,
	# process also wordpressblog.002.xml, wordpressblog.nnn.xml...
	my %export_info;
	if (my ($base_part, $seq_num) = $wp_export_filename =~ /^(.+)\.(\d+)\.xml$/) {
		my $max_seq = '9' x length($seq_num);
		for my $seq_part ($seq_num ... $max_seq) {
			my $cur_export_file = "$base_part.$seq_part.xml";
			last unless -e $cur_export_file;

			export_single_wpfile($cur_export_file, $output_dir, $skipimages, \%export_info);
		}
	}
	else {
		# Single export file only
		export_single_wpfile($wp_export_filename, $output_dir, $skipimages, \%export_info);
	}

	my @all_categories = sort {"\L$a" cmp "\L$b"} keys $export_info{categories};

	print "Writing to config file $output_dir/site.conf...\n";
	generate_config_file($output_dir, 'site.conf',
		$export_info{blog_title}, $export_info{blog_description}, \@all_categories);
}

1;
