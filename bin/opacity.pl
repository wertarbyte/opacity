#!/usr/bin/perl
#
# Retrieve books and their return date
# from the public library in Duisburg, German
#
# by Stefan Tomanek <stefan@pico.ruhr.de

use strict;

use LWP::UserAgent;
use HTML::TreeBuilder::XPath;
use Date::Parse;
use Data::Dumper;

my $user = $ARGV[0];
my $pass = $ARGV[1];

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

sub parse_date {
    my ($datestr) = @_;
    if ($datestr =~ s/^([0-9]{2})\.([0-9]{2})\.([0-9]{4})$/\3:\2:\1/) {
        return str2time($datestr);
    }
    return undef;
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
        my @dates = map { parse_date($_) } $tree->findnodes_as_strings( '//form/table/tr/td[3]' );
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

print Dumper( [ get_books($user, $pass) ] );
