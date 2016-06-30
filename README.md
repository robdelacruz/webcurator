# Web Curator 
*Developed by [Rob de la Cruz](https://twitter.com/robdelacruz) robdelacruz@yahoo.com*

See the [license section](#license).

## Introduction

Web Curator can be used to:

- Maintain a static website. Write web pages as plain text and run a utility to generate html and css files to be uploaded to your web host.
- Take an exported Wordpress site and convert it to a static website.

A [sample website](https://dl.dropboxusercontent.com/u/27739534/webtest/somecommentary/articles.html) generated using *Web Curator*.

## Issues

Here's the [list](https://github.com/robdelacruz/webcurator/issues) of pending bugs and todo items.

## Setup and Dependencies

Web Curator runs on Linux, Mac and Windows and requires [Perl](https://www.perl.org/get.html) to be installed.

Steps to set up in Linux/Mac:

1. Download the project using `git clone` or direct download.
2. Run `install_cpan_dependencies.sh` to install module dependencies.
3. Add an alias to your .bashrc file: `alias webc='<path to project here>/webc.pl'`

Run `webc` on the shell to verify that the alias you set up in *step 3* is working.

## Generate a static website from input text files.

  1. Run the following command to initialize a new source directory:

```
webc --newsourcedir <target directory>

Ex. webc --newsourcedir robs_website
```

This will create a new directory that contains sample input files containing the basic format of an article page, as well as a default *site.conf* configuration file.

  2. In the target directory you specified from the previous step, you'll find the sample input file `article1.txt` which contains the basic format of an input file. Each input file corresponds to a web page that will appear in the target website. You can think of the input file as containing a single text article or blog post that will show up in the completed website.

Sample input file:

```
WEBC 1.0
Title: Sample Article Title
Date: 2016-01-01
Author: sample author
Type: article
Format: markdown
Topic: Topic 1, Topic 2
Tags: Tag 1, Tag 2

This is a sample article.
```

The input file always starts with `WEBC 1.0` on the first line. This indicates to the *webc* utility that this file contains valid page content.

You can set the title, date, author, and other metadata that describes the article in the list of header fields. For example, to specify the title of the article, set the *Title* field:

```
Title: Sample Article Title
```

The article content is separated from the header fields by a single blank line as indicated in the sample input file provided.

To add another web page, just create a new text input file. The *webc* utility will read all the input files and curate them into a website in a later step.

You can also configure the website settings that control various properties in the `site.conf` file. I'll document these fields in a future update but feel free to experiment with the settings.

  3. Generate the static website based on the current set of input files

When you're done editing input files and want to create a static website representation of it, run the following:

```
webc --sourcedir <target directory from step 1>

Ex. webc --sourcedir robs_website
```

This will create a new directory `site/` that contains the website files you can upload to your web host provider. Open the file `site/index.html` in your browser to view the generated website.

Here's the list of web pages generated: 

```
index.html  
articles.html
archives.html  
<article title 1>.html  
<article title 2>.html  
<article title 3>.html  
<topic 1>.html
<topic 2>.html
<tag 1>.html
<tag 2>.html
style.css  
```

You can edit these html files directly if you want but remember that they will be overwritten if you regenerate the website again in the future.

## Exporting a Wordpress site to Web Curator

`webc` can also take a an exported wordpress xml file as input and translate the existing wordpress posts into input text files. Or if you prefer, you can convert the exported wordpress xml file into a website in one step. Here's how to do it:

  1. Export Wordpress blog into XML

If you're using a hosted wordpress.com account, you can export your blog by logging into wordpress.com and navigating to `https://<your blog id>/wp-admin/export.php?type=export`, and select *Download Export File* to download the wordpress xml file that contains all your content.

  2. Translate exported xml file into a static website

Once you have the exported wordpress xml file, you can convert it directly to a static website in one step:

```
webc --exportwp <wordpress xml file> --autogen
```

This will create a new directory `site/` containing the translated website files.

The utility will automatically download any images you uploaded to wordpress that you have referenced in an existing post. If you have a lot of images, this might slow down the translation, so *webc* has the option of skipping downloading images and just referencing the images from the original wordpress site. Here's the command-line switch to do that:

```
webc --exportwp <wordpress xml file> --autogen --skipimages
```

If you prefer not to generate the website directly, but instead translate the wordpress xml file into a set of input text files, just omit the *--autogen* switch:

```
webc --exportwp <wordpress xml file> 
```

This will create a new directory *output/* containing the input text files. This is handy if you want to convert an existing wordpress blog into Web Curator format, then add new articles to it.

## License

This is subject to the terms of the Mozilla Public License 2.0. You can obtain one at http://mozilla.org/MPL/2.0/ .

