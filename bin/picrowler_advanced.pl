#!/usr/bin/env perl

use strict; 
use warnings;

use IO::All;
use LWP::Simple;
use URI;
use Web::Scraper;

my $nodes;
my $edges;

my $nodes_count = 0;

sub is_valid {
    my $uri = URI->new( shift );
    my $is_valid = 1;
    if( ref( $uri ) ne 'URI::http' ) {
        warn "[$uri] not valid";
        $is_valid = 0;
    }
    return $is_valid;
}

sub find_or_create_node {
    my $url = shift;
    my $id  = undef;    
    if( defined $nodes->{ $url } ) {
        $id = $nodes->{ $url };
    }
    else {
        $id = $nodes->{ $url } = ++$nodes_count; 
    }
    return $id;
}

my ( $max_depth, @seed ) = @ARGV or die( 'need depth and url(s)' );

my @already_visited = ();
my $depth = 0;
#my @to_visit = @seed;

my @to_visit = grep{ is_valid( $_ ) } @seed;

find_or_create_node( $_ ) for( @to_visit );

# Création du scraper
my $links_scraper = scraper {
    process "a", "links[]" => '@href';
};

while( $depth <= $max_depth && @to_visit ) {

    print "crawling depth $depth\n";

    my @links = ();

    for my $url ( @to_visit ) {

        my $sec = sleep( rand( 3 ) );
        print "sleeping $sec sec\n";


        # On récupère la page
        if( my $content = get( $url ) ) {
#            while ( $content =~ m/<a href="([^"]+)"/gi) { 
#                my $link = $1;
#                print "$link found\n";
#                push @links, $link;
#            }

            # On scrape son contenu pour récupérer les tags A
            my $result = $links_scraper->scrape( $content );

            my $id_source = find_or_create_node( $url );

            for my $link ( @{ $result->{ links } } ) {
                my $link_uri = URI->new_abs( $link, $url );
#                print "$link_uri\n";
                push @links, { id => $id_source, url => $link_uri->as_string };
            }

           
        }
        # On l'ajoute dans notre base de already_visited
        push @already_visited, $url;
        print "[$url] visited.\n";
    }
    @to_visit = ();

    for my $link ( @links ) {

        my $url_to_check = $link->{ url };
        my $id_source = $link->{ id };

        # Quelles pages a-t-on déjà visité ?
        my $to_push = 0;
        # On vérifie qu'il faut crawler cette url
        for my $url_visited ( @already_visited ) {
            if( $url_to_check eq $url_visited ) { 
                $to_push = 0; last; 
            }
            $to_push = 1;
        }
        
        push @to_visit, $url_to_check
            if( $to_push && !grep{ $_ eq $url_to_check } @to_visit && is_valid( $url_to_check ) );			

        my $id_target = find_or_create_node( $url_to_check );
        $edges->{ "$id_source-$id_target" } ++ unless( $id_source == $id_target );
    }
    $depth++;
}
print "end crawling.\nwriting gdf...\n";

my $out = io( 'crawl.gdf' );

"nodedef> name VARCHAR, label VARCHAR, site VARCHAR\n" > $out;

for my $url ( keys %$nodes ) {
    my $id = $nodes->{ $url };
    my $host = URI->new( $url )->host;
    "v$id, '$url', '$host'\n" >> $out;
}

"edgedef> node1 VARCHAR, node2 VARCHAR, count INT\n" >> $out;

for my $ids ( keys %$edges ) {
    my ( $id_source, $id_target ) = split( /-/, $ids );
    my $count = $edges->{ $ids };
    "v$id_source, v$id_target, $count\n" >> $out;
}

print "end.\n";
__END__

1. Quels liens on extrait ?
2. Regexp bof, on va utiliser un scraper
3. On va créer un GDF
