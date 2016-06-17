#!/usr/bin/perl

use v5.14;


my $caption1 = <<'EOT';
[caption id="attachment_3411" align="aligncenter" width="300"]<a href="https://3rdworldgeeks.files.wordpress.com/2014/11/dc-movie-timeline.png" rel="attachment wp-att-3411"><img class="size-medium wp-image-3411" src="https://3rdworldgeeks.files.wordpress.com/2014/11/dc-movie-timeline.png?w=300" alt="That's a long time!" width="300" height="284" /></a> Up to 2020? Wow! That's a lot of planning![/caption]
EOT

my $caption2 = <<'EOT';
[caption id="attachment_91183" align="aligncenter" width="300"]<a href="https://3rdworldgeeks.files.wordpress.com/2016/03/superman-wonder-woman-and-batman.jpg" rel="attachment wp-att-91183"><img class="size-medium wp-image-91183" src="https://3rdworldgeeks.files.wordpress.com/2016/03/superman-wonder-woman-and-batman.jpg?w=300" alt="I hope she doesn't just swoop in to save the day..." width="300" height="150" /></a> I hope she doesn't just swoop in to save the day...[/caption]

[caption id="attachment_3411" align="aligncenter" width="300"]<a href="https://3rdworldgeeks.files.wordpress.com/2014/11/dc-movie-timeline.png" rel="attachment wp-att-3411"><img class="size-medium wp-image-3411" src="https://3rdworldgeeks.files.wordpress.com/2014/11/dc-movie-timeline.png?w=300" alt="That's a long time!" width="300" height="284" /></a> Up to 2020? Wow! That's a lot of planning![/caption]
EOT

my $youtube = <<'EOT';
[youtube=https://www.youtube.com/watch?v=4gO8g90z3VU]
https://www.youtube.com/watch?v=4gO8g90z3VU
https://youtube.com/watch?v=4gO8g90z3VU

[youtube https://youtu.be/xFVDNTXIC_Y ]
http://www.youtu.be/xFVDNTXIC_Y
http://youtu.be/xFVDNTXIC_Y
EOT

say $caption1;
say $caption2;
say $youtube;


$caption1 =~ s/\[caption\s+.*?\]\s*(.+>)\s*(.*?)\s*\[\/caption\]/<figure>\1<figcaption>\2<\/figcaption><\/figure>/g;

$caption2 =~ s/\[caption\s+.*?\]\s*(.+>)\s*(.*?)\s*\[\/caption\]/<figure>\1<figcaption>\2<\/figcaption><\/figure>/g;

$youtube =~ s/(https?:\/\/(?:www\.)?youtu\.?be\S+)/<a href="\1">\1<\/a>/g;
$youtube =~ s/\[youtube[\s=]\s*(.+?)\s*\]/\1/g;

say "caption1 transformed:\n$caption1";
say "caption2 transformed:\n$caption2";
say "youtube transformed:\n$youtube";

