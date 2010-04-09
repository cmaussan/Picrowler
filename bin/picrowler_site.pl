#!/usr/bin/env perl

use strict; 
use warnings;

use IO::All;
use LWP::UserAgent;
use URI;
use Web::Scraper;

### Gestion des params de ligne de commande ###

my ( $max_depth, $max_pages_count, $max_distance, @seed_urls ) = @ARGV or die( 'need a lot of things ;)' );

print "Picrowler ---\n";
print "max_depth = $max_depth\n";
print "max_pages_count = $max_pages_count\n";
print "max_distance = $max_distance\n";

### Gestion de la base de données ###

### Initialisation de LWP ###
my $agent = LWP::UserAgent->new;
$agent->agent( 'Picrowler - http://github.com/cmaussan/Picrowler' );

### Initialisation du scraper ###
my $scraper = scraper {
    process "a", "links[]" => '@href';
};

my @sites_to_visit = grep { is_valid( $_ ) } @seed_urls;
my @sites_already_visited = ();

my $distance = 0;

while( $distance <= $max_distance ) {
    
    for my $site_start_url ( @sites_to_visit ) {

        next unless( is_valid( $site_start_url ) );

        my $site_site_uri = site_uri( $site_start_url );
        next if( grep{ $_ eq $site_site_uri->canonical->as_string } @sites_already_visited );

        push @sites_to_visit, @{ crawler( $site_start_url, $site_site_uri ) };
        push @sites_already_visited, $site_site_uri->canonical->as_string;     

        $distance++;
    }

}

### Vérificateur d'URL ###
sub is_valid {
    my $url = shift;
    my $uri = ( ref $url && ref $url =~ /^URI/ ) ? $url : URI->new( $url );

    if( ref( $uri ) ne 'URI::http' ) {
        warn "[$uri] not valid";
        $uri = undef;
    }
    return $uri;
}


### Définisseur de site ###
sub site_uri {
    my $uri = is_valid( shift );

    return undef unless( $uri );  

    # Heuristique de site, on met ce qu'on veut ici
    # Par défaut on renvoie le host canonisé
    return URI->new( $uri->scheme . '://' . $uri->host )->canonical;

}

sub is_outlink {
    my ( $site_uri, $link_uri ) = @_;
    my $site_pattern = $site_uri->canonical->as_string;
    return ( $link_uri->canonical->as_string !~ /^$site_pattern/ ) ? 1 : 0;
}

### Crawler de site ###
sub crawler {
    my ( $start_url, $site_uri ) = @_;

    print "crawling [$site_uri] ($start_url) :\n";

    my @to_visit = ( $start_url );
    my @already_visited = ();
    my @outlinks = ();

    my $depth = 0;
    my $pages_count = 0;

    while( $depth <= $max_depth && $pages_count <= $max_pages_count && @to_visit ) {

        print "--- before\n";
        print "... depth = $depth / $max_depth\n";
        print "... pages_count = $pages_count / $max_pages_count\n";
        print "... " . scalar( @to_visit ) . " urls to crawl\n";

        my @links = ();
        
        for my $url ( @to_visit ) {
            
            last unless( $pages_count <= $max_pages_count );

            print "... crawling page [$url]\n";

            my $response = $agent->get( $url );
            if( $response->is_success ) {
#                use YAML::XS;
#                die( Dump $response );
                next unless( $response->header( 'content-type' ) =~ m!text/html! );
                $url = $response->request->uri->canonical->as_string;
                my $result = $scraper->scrape( $response->content );
                
                for my $link ( @{ $result->{ links } } ) {
                    my $link_uri = URI->new_abs( $link, $url );
                    if( is_outlink( $site_uri, $link_uri ) ) {
#                        print "... outlink [$link_uri] found\n";
                        push @outlinks, $link_uri->as_string;
                    }
                    else {
#                        print "... inlink [$link_uri] found\n";
                        push @links, $link_uri->as_string;
                    }
                 }

            }
            else {
                warn "[$url] impossible to get : " . $response->status_line;
                next;
            }

            push @already_visited, $url;
            $pages_count++;
        }

        print "... found " . scalar( @links ) . "\n";

        @to_visit = ();
        
        for my $url_to_check ( @links ) {
            my $to_push = 1;
            for my $url_visited ( @already_visited ) {
                if( $url_to_check eq $url_visited ) { 
                    $to_push = 0; last; 
                }
                $to_push = 1;
            }
            push @to_visit, $url_to_check
                if( $to_push && !grep{ $_ eq $url_to_check } @to_visit );				
        }

        $depth++;

        print "--- after\n";
        print "... depth = $depth / $max_depth\n";
        print "... pages_count = $pages_count / $max_pages_count\n";
        print "... " . scalar( @to_visit ) . " urls to crawl\n";

    }

    \@outlinks;
}


