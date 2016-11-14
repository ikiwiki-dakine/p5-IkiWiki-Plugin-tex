# A renderer based on tex4ht, using Thomas Schwinge's texinfo plugin as 
# a skeleton.

# Copyright © 2008 David Bremner <bremner@unb.ca>
# Copyright © 2007 Thomas Schwinge <tschwinge@gnu.org>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.



package IkiWiki::Plugin::tex4ht;
use Data::Dumper;
use warnings;
use strict;
use IkiWiki 2.00;
use File::Basename;
use Cwd;

my %metaheaders;

# From `Ikiwiki/Plugins/teximg.pm'.
sub create_tmp_dir ($)
{
    # Create a temp directory, it will be removed when ikiwiki exits.
    my $base = shift;

    my $template = $base . ".XXXXXXXXXX";
    use File::Temp qw (tempdir);
    my $tmpdir = tempdir ($template, TMPDIR => 1, CLEANUP => 1);
    return $tmpdir;
}

sub import
{
    hook (type => "filter", id=>"tex",call=>\&filter);
    hook (type => "htmlize", id => "tex", call => \&htmlize);
    hook (type => "pagetemplate", id=>"tex4ht", call=>\&pagetemplate);
}

sub getopt () { #{{{
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("texoverride=s" => \$config{texoverride});
} #}}}

sub filter(@){
    my %params = @_;
    my $page = $params{page};
    my $content =$params{content};

    return $content if ($content !~ m/\s*\\documentclass/);
    debug("calling filter for $page ".pagetype($page));
    $content =~ s/(\[\[[\w\s\|\/\.]+\]\])/\\HCode{$1}/g;
    return $content;
}

sub htmlize (@)
{
    my %params = @_;
    my $page = $params{page};

    my $pid;
    my $sigpipe = 0;
    $SIG{PIPE} = sub
    {
	$sigpipe = 1;
    };

    my $origdir=getcwd();

    my $tmp = eval
    {
	create_tmp_dir ("tex4ht")
    };

    my $texname='tex4iki';
    my $pagedir= $config{srcdir} . '/' . dirname ($pagesources{$page});
    my $destdir = File::Spec->rel2abs($config{destdir});
    $pagedir = File::Spec->rel2abs( $pagedir );

    if (! $@ &&
	# `htlatex' can't work directly on stdin.
	writefile ("$texname.tex", $tmp, $params{content}) == 0)
    {
	return "couldn't write temporary file";
    }

    chdir $tmp || die "$!";

    # so includes from same directory work
    $ENV{TEXINPUTS}= $pagedir.':'.$ENV{TEXINPUTS};
    $ENV{TEX4HTINPUTS}= $pagedir.':'.$ENV{TEXINPUTS};
    $ENV{BIBINPUTS}= $pagedir.':'.$ENV{BIBINPUTS};
    
    if (defined $config{texoverrides}){
	$ENV{TEXINPUTS}= $config{texoverrides}.':'.$ENV{TEXINPUTS};
	$ENV{TEX4HTINPUTS}= $config{texoverrides}.':'.$ENV{TEX4HTINPUTS};
    }

    # Add support for Unicode input
    my @htlatex_args = ("xhtml, charset=utf-8", "-cunihtf -utf8");

    debug("TEXINPUTS=".$ENV{TEXINPUTS});
    debug("calling htlatex for ".$params{page});
    #system(qw(latexmk -dvi),$texname);
    #system(qw(mk4ht htlatex),$texname);
    system(qw(htlatex),$texname,@htlatex_args);
    my $logfile = readfile("$texname.log") ;
    my $need_biber = $logfile =~ /\QPackage biblatex Warning: Please (re)run Biber on the file\E/m;
    if( $need_biber ) { # note: this would be better if it was based on latexmk
      system(qw(biber), $texname);
    } else {
      system(qw(bibtex), $texname);
    }
    system(qw(htlatex),$texname,@htlatex_args);

    foreach my $png (<*.png>){
	my $destpng=$page."/".$png;
	will_render($params{page},$destpng);
	my $data=readfile($png,1);
	writefile($png,$destdir."/".$page,$data,1) || die "$!";
    }

    my $stylesheet=$page."/tex4ht.css";
    will_render($params{page},$stylesheet);

    my $css=readfile("$texname.css");
    writefile("tex4ht.css",$destdir."/".$params{page},$css) || die "$!";


    push @{$metaheaders{$page}}, '<link href="'.urlto($stylesheet, $page).
	'" rel="stylesheet"'.
	' type="text/css" />';

    open(IN,"$texname.html") || die "$!";
    local $/ = undef;

    my $ret = <IN>;
    close IN;

    # fix links back to same page
    # e.g.,
    #   <a href="tex4iki.html#anchor">
    # to
    #   <a href="#anchor">
    $ret =~ s/(<a\s+href=")tex4iki.html/$1/sg;

    # Cut out the interesting bits.
    $ret =~ s/.*<\/head>//s;
    $ret =~ s/<\/body>.*//s;

    chdir $origdir || die "could not restore working directory";
    return $ret;
}


sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (exists $metaheaders{$page} && $template->query(name => "meta")) {
		# avoid duplicate meta lines
		my %seen;
		$template->param(meta => join("\n", grep { (! $seen{$_}) && ($seen{$_}=1) } @{$metaheaders{$page}}));
	}
}

1
