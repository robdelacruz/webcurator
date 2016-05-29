# Web Curator

Web Curator is a static site generator. It generates a complete website given an input list of text files.

## Goals

Generate a website from an input list of text files.

Sample input file:

	WEBC 1.0  
	Title: The title of the web page  
	Date: 2016-04-06 15:30  
	Author: rob  
	Type: article  
	Format: markdown
	  
	The text of the web page in markdown format or direct html depending on the 'Format' attribute.  

Example - Given three input files: article1.txt, article2.txt, article3.txt
Generate the website with this command:

	./webc.pl article1.txt article2.txt article3.txt  

Or use wildcards:

	./webc.pl *.txt  

This generates the set of website pages which can be uploaded to a web host:

	index.html  
	archives.html  
	<article title 1>.html  
	<article title 2>.html  
	<article title 3>.html  
	style.css  


