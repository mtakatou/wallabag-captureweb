#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Encode;
use File::Slurp;
use File::Temp;
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use JSON;
use LWP::UserAgent;
use Time::Progress;
use Try::Tiny;
use XML::Simple;

my $dpi=600;
my $GSOPT   ="-dSAFER -dBATCH -dNOPAUSE -dNOPROMPT -dMaxBitmap=500000000 -dAlignToPixels=0 -dGridFitTT=2 -sDEVICE=pngalpha -r${dpi}x$dpi";

my $do_all=0;

my $client_id    =$ENV{WALLABAG_CLIENT_ID};
my $client_secret=$ENV{WALLABAG_CLIENT_SECRET};
my $wallabag_url =$ENV{WALLABAG_URL};
my $wallabag_username     =$ENV{WALLABAG_USERNAME};
my $wallabag_password     =$ENV{WALLABAG_PASSWORD};
my $useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.14; rv:65.0) Gecko/20100101 Firefox/65.0";

# helenのhttpにする。万が一漏れても外からはアクセスできないし、id/pass不要になるんじゃね？
my $dav_url = $ENV{DAV_URL};
my $dav_username = $ENV{DAV_USERNAME};
my $dav_password = $ENV{DAV_PASSWORD};

GetOptions(
    "clientid=s"     => \$client_id,
    "clientsecret=s" => \$client_secret,
    "url=s"          => \$wallabag_url,
    "wallabagusername=s"     => \$wallabag_username,
    "wallabagpassword=s"     => \$wallabag_password,

    "davurl=s"      => \$dav_url,
    "davusername=s" => \$dav_username,
    "davpassword=s" => \$dav_password,

    "useragent=s" => \$useragent,
    );

# tokenくださいな
#
my $json=post($wallabag_url . "/oauth/v2/token",
	   {
	       "grant_type"    => "password",
               "client_id"     => $client_id,
	       "client_secret" => $client_secret,
	       "username"      => $wallabag_username,
	       "password"      => $wallabag_password
	   });
my $token=$json->{"access_token"};

my @all;
my %entry;

my $url=$wallabag_url . "/api/entries.json";
while($url){
    printlog("list: $url");
    $json=get($url);
    foreach my $item (@{ $json->{_embedded}->{items} }){
	my $id=$item->{id};
	my $preview=$item->{preview_picture};
	push(@all, $id);
	if(not $preview){
	    $entry{$id}=$item->{url};
	}
    }
    $url=$json->{_links}->{"next"}->{href};
}

printlog("got " . ( $#all + 1 ) . " entries");
#print Dumper %entry;

my $progress = Time::Progress->new();
my $max=keys(%entry);
$progress->restart(min => 0,
		   max => $max);
my $count=0;

while(my ($id,$url)=each(%entry)){
    printlog("$count / $max " . 
	     $progress->report("elapsed: %L eta: %E: %p %40b\n", $count));
    $count++;
    printlog("url: $url");

    my $img;

    if($url =~ /.pdf$/i){
	$img=getImageFromPDF($url);
    }

    if(not $img){
	$img=getScreenshot($url);
    }
    
    if($img){
	my $file="/tmp/${id}.jpeg";
	my $davpath="${dav_url}${id}.jpeg";
	write_file($file, $img);
	my $r=curl("-T \"$file\" \"$davpath\"");
	if($r){
	    printlog("failed to upload image to dav : $davpath");
	    next;
	}
	patch($wallabag_url . "/api/entries/$id.json",
	      {
		  "preview_picture" => $davpath
	      });
    }
}

#削除されたエントリーの画像を削除
my $list=list($dav_url);

foreach my $file (@$list){
    if($file =~ /(\d+).jpeg/){
	my $id=$1;
	my @found=grep{$_ == $id}(@all);
	next if($#found == 0);
	my $path="$dav_url/$id.jpeg";
	printlog("missing $id in wallabag, delete $path");
	curl("-X DELETE '$path'");
    }
}
exit;

sub list
{
    my $url=shift;

    my @dir;
    my $tmpfile=tmpnam() . ".xml";
    curl("--request PROPFIND -H 'Content-Type: text/xml' -H 'Depth: 1' \"$url\" -o $tmpfile");
    try{
	my $xml=XML::Simple->new;
	my $data=$xml->XMLin($tmpfile);
	unlink($tmpfile);
	foreach my $e (@{ $data->{'D:response'} }){
	    if(exists($e->{'D:href'})){
		my $name=$e->{'D:href'};
		Encode::_utf8_off($name);
		$name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('H2', $1)/eg;
		Encode::_utf8_on($name);
		push(@dir, $name);
	    }else{
		print Dumper $e;
	    }
	}
    }catch{
	return undef;
    };
    return \@dir;
}


sub curl
{
    my $arg=shift;

    my $opt="";
    if($dav_username and $dav_password){
	$opt="--insecure --user \"$dav_username:$dav_password\" --anyauth";
    }
    
    my $r=system("curl --silent $opt $arg");
    return $r;
}
    
sub getScreenshot
{
    my $url=shift;

    my $pngfile=tmpnam() . ".png";
    my $jpegfile=tmpnam() . ".jpeg";
    
    system("python3 /screenshot.py --url '$url' --filename '$pngfile' -w 1200x8000 --ua '$useragent'");    
    if(-e $pngfile){
	system("file $pngfile");
	system("convert -trim $pngfile $jpegfile");
	system("jpegoptim --strip-all -m95 -t $jpegfile");
	if(`identify -format "%[width],%[height]" $jpegfile` eq "1,1"){
	    return undef;
	}
	my $data=read_file($jpegfile);
	return $data;
    }else{
	return undef;
    }
}

sub post
{
    return request("post", @_);
}

sub patch
{
    return request("patch", @_);
}

sub get
{
    return request("get", @_);
}

sub request
{
    my $type=shift;
    my $url=shift;
    my $arg=shift;

    my $jsontxt;
    my $lwpreq;
    my $lwpua = LWP::UserAgent->new;
    $lwpua->timeout(1000);

    if($type =~ /post/i){
	$lwpreq= HTTP::Request->new(POST => $url);
    }elsif($type =~ /get/i){
	$lwpreq= HTTP::Request->new(GET => $url);
    }elsif($type =~ /patch/i){
	$lwpreq= HTTP::Request->new(PATCH => $url);	
    }else{
	die;
    }

    if($token){
	$lwpreq->header("Authorization" => "Bearer $token");
    }

    if($arg){
	$lwpreq->header('Content-Type' => 'application/json');
	my $jsontxt=encode_json($arg);
	$lwpreq->content($jsontxt);
    }

    #fire!
    my $lwpres= $lwpua->request($lwpreq);

    if($lwpres->code() != 200){
	printlog($lwpres->content);
	return {};
    }
    
    if($lwpres->code() == 500){
	printlog($lwpres->content);
	return {};
    }

    my $txt =$lwpres->content;
    my $data;
    try{
	$data = decode_json($txt);
    }catch{
	printlog("failed to decode json");
	$data = {};
    };

    return $data;
}

sub getImageFromPDF
{
    my $url=shift;
    
    my $lwpreq;
    my $lwpua = LWP::UserAgent->new;
    $lwpua->timeout(1000);
    $lwpua->agent($useragent);

    $lwpreq= HTTP::Request->new(GET => $url);
    my $lwpres= $lwpua->request($lwpreq);

    if($lwpres->code() != 200){
	return undef;
    }

    my $pdffile=tmpnam() . ".pdf";
    my $pngfile=tmpnam() . ".png";
    my $jpegfile=tmpnam() . ".jpg";
    write_file($pdffile, $lwpres->content);
    system("gs $GSOPT -dFirstPage=1 -dLastPage=1 -sOutputFile=$pngfile $pdffile");
    system("convert -trim $pngfile $jpegfile");
    system("jpegoptim --strip-all -m95 -t $jpegfile");
    if(`identify -format "%[width],%[height]" $jpegfile` eq "1,1"){
	return undef;
    }
    if(-e $jpegfile){
	return read_file($jpegfile);
    }
    return undef;
}

sub printlog{
    my $msg=shift;
    
    foreach my $line (split("\n", $msg)){
	chomp($line);

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	    localtime(time);
	
	my $date=sprintf('[%04d/%02d/%02d %02d:%02d:%02d]',
			 $year + 1900,
			 $mon + 1,
			 $mday,
			 $hour,
			 $min,
			 $sec);

	if(utf8::is_utf8($line)){
	    print "$date " . Encode::encode("utf8", $line) . "\n";
	}else{
	    print "$date $line\n";
	}
	STDOUT->flush()
    }
    return;
}
