#!/usr/bin/perl
#
# Retrieve borrowed books and their return date
# from the public library in Duisburg, Germany
#
# by Stefan Tomanek <stefan@pico.ruhr.de>
#
# Usage:
#
# Display all books borrowed by <USERNAME>:
#
#   opacity.pl -u USERNAME -p PASSWORD --all
#
# Only display books that are due in the next 4 days:
#
#   opacity.pl -u USERNAME -p PASSWORD --due --limit 4
#
# (very handy for a cronjob)

use strict;

use LWP::UserAgent;
use HTML::TreeBuilder::XPath;
use Date::Calc qw(Decode_Date_EU Today Date_to_Time Delta_Days);
use Date::Format;
use Getopt::Long;

my ($user, $pass);
# what to show
my $all = 0;
my $due = 0;
# show books 4 days before they are due
my $limit = 4;

GetOptions(
    "user|username|u=s" => \$user,
    "pass|password|p=s" => \$pass,
    "all|a!"            => \$all,
    "due|d!"            => \$due,
    "limit|l=i"         => \$limit
) || die "Unable to parse command line!";

unless (defined $user && defined $pass) {
    die "No user information given.";
}

# enforce default operation procedure
unless ($all || $due) {
    $all = 1;
    $due = 0;
}

my $ua = new LWP::UserAgent();
$ua->cookie_jar( {} );

sub get_book_details {
    my ($ua, $id) = @_;
    my $url = "http://opac.stadtbibliothek.duisburg.de/opac/ftitle.C?LANG=de&FUNC=full&DUM2=0&".$id."=YES";
    my $r = $ua->get($url);
    if ($r->is_success) {
        my $tree = HTML::TreeBuilder::XPath->new;
        $tree->parse( $r->decoded_content() );
        my $title = $tree->findvalue('//td[substring( text(), 1, 5 ) = "Titel"]/following-sibling::td[1]/text()');
        chop $title;
        
        return { title => $title };
    } else {
        die $r->status_line();
    }
}

sub get_books {
    my ($user, $pass) = @_;
    # FUNC: login medk vorm gebk kurz
    my $r = $ua->post(
        "http://opac.stadtbibliothek.duisburg.de/opac/user.C",
        {
            FUNC     => 'medk',
            BENUTZER => $user,
            PASSWORD => $pass
        }
    );

    my @books;
    if ($r->is_success) {
        my $data = $r->decoded_content();
        my $tree = HTML::TreeBuilder::XPath->new;
        $tree->parse( $data );
        my @dates = map { [ Decode_Date_EU($_) ] } $tree->findnodes_as_strings( '//form/table/tr/td[3]' );
        my @codes = $tree->findnodes_as_strings( '//form/table/tr/td[4]' );
        my @titles = $tree->findnodes_as_strings( '//form/table/tr/td[7]' );
        my @ids = $tree->findvalues( '//form/table/tr/td/a/@href' );
        while (@dates) {
            my ($id) = (pop @ids) =~ m/'([0-9]+)'/g;
            push @books, {
                returndate => pop @dates,
                barcode    => pop @codes,
                title      => pop @titles,
                details    => get_book_details($ua, $id)
            };
        }
    } else {
        die $r->status_line;
    }
    return @books;
}

sub show_book {
    my ($book) = @_;
    my @now = Today();
    my @return = @{ $book->{returndate} };
    
    my @time = localtime( Date_to_Time(@return,0,0,0) );
    my $strReturn = strftime('%Y-%m-%d', @time );
    my $daysLeft = Delta_Days(@now, @return);

    if ($all || $daysLeft <= $limit) {
        print " == ".$book->{title}." [".$book->{barcode}."] == \n";
        print $strReturn, " -> $daysLeft days left\n\n";
    }
}

for ( get_books($user, $pass) ) {
    show_book($_);
}
