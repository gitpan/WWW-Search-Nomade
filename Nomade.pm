#
# Nomade.pm
# by Alain Barbet alian@alianwebserver.com
# Copyright (C) 2000
# $Id: Nomade.pm,v 1.2 2001/10/03 12:08:13 alian Exp $
#

package WWW::Search::Nomade;
require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
@ISA = qw(WWW::Search Exporter);
$VERSION = ('$Revision: 1.2 $ ' =~ /(\d+\.\d+)/)[0];

use Carp ();
use strict;
use WWW::Search(qw (generic_option strip_tags));
require WWW::SearchResult;

# private
sub native_setup_search
	{
    	my($self, $native_query, $native_options_ref) = @_;
    	$self->user_agent('alian');
    	$self->{_next_to_retrieve} = 0;
  	$self->{'search_base_url'} = 'http://rechercher.nomade.fr';  	
	if (!defined($self->{_options})) {
	$self->{_options} = 
	  { 
	   's' 	=> $native_query,
	   'GL'     => "INTL",
	   'ok.x'   => 1,
         'ok.y'   => 1,
	   'search_url' => $self->{'search_base_url'}.'/recherche.asp'
        };}
    	my($options_ref) = $self->{_options};
    	if (defined($native_options_ref)) 
    		{
		# Copy in new options.
		foreach (keys %$native_options_ref) 
		  {$options_ref->{$_} = $native_options_ref->{$_};}
    		}
    	# Process the options.
    	# (Now in sorted order for consistency regarless of hash ordering.)
    	my($options) = '';
    	foreach (sort keys %$options_ref) 
    		{
		# printf STDERR "option: $_ is " . $options_ref->{$_} . "\n";
		next if (generic_option($_));
		$options .= $_ . '=' . $options_ref->{$_} . '&' 
		  if (defined $options_ref->{$_});
    		}

    	# Finally figure out the url.
    	$self->{_base_url} = $self->{_next_url} 
	  = $self->{_options}{'search_url'} ."?" . $options;
    	print STDERR $self->{_base_url} . "\n" if ($self->{_debug});	
	}

# private
sub create_hit
  {
    my ($self,$url,$titre,$description)=@_;
    my $hit = new WWW::SearchResult;
    $hit->add_url($url);
    $hit->title(strip_tags($titre));
    $hit->description(strip_tags($description));
    print STDERR " *** Found item\n\tUrl: $url\n",
	"\tTitle:",$hit->title(),"\n\tDescription:",$hit->description(),"\n"	
	  if ($self->{_debug});
    push(@{$self->{cache}},$hit);
    return 1;
  }

# private
sub native_retrieve_some
  {
    my ($self) = @_;
    my($hits_found) = 0;
    my ($buf,$langue);
    print "DEBUG MODE\n" unless $self->{_debug}==0;
    #fast exit if already done
    return undef if (!defined($self->{_next_url}));
    print STDERR "WWW::Search::Nomade::native_retrieve_some: fetching " .
	$self->{_next_url} . "\n" if ($self->{_debug});
    my($response) = $self->http_request('GET', $self->{_next_url});
    $self->{response} = $response;
    print STDERR "WWW::Search::Nomade GET  $self->{_next_url} return ",
	$response->code,"\n"  if ($self->{_debug});
    if (!$response->is_success) {return undef;};
    $self->{_next_url} = undef; 

    # parse the output
    my($HEADER, $HITS, $INHIT, $INLINK, $TRAILER, 
	 $POST_NEXT, $FRANCO, $MONDIAL,$PREMIUM) = (1..10);  # order matters
    my($state) = ($HEADER);
    my($raw) = '';
    foreach ($self->split_lines($response->content())) {#print $_,"\n";
	next if m@^$@; # short circuit for blank lines
	######
	# HEADER PARSING: find the number of hits
	#
	if ($state == $HEADER && 
	    /Il n\'existe pas de document r&eacute;pondant &agrave; votre requ/)
	  {
	    $self->approximate_result_count(0);
	    $state = $TRAILER;
	    print STDERR "No result\n"  if ($self->{_debug});
	  }
	elsif ($state == $HEADER &&
		 m!<B>(\d+)</B> page\(s\)!)
	  {
	    $self->approximate_result_count($1);
	    $state = $HITS;
	    $langue=$MONDIAL;
	    print STDERR "$1 English result\n"  if $self->{_debug};
	  }
	elsif ($state == $HEADER &&
		 m!<B>&nbsp;&nbsp;&nbsp;Plus de 200 sites!)
	  {
	    $self->approximate_result_count(200);
	    $state = $HITS;
	    $langue=$FRANCO;
	    print STDERR "More than 200 result.Premium\n"  if $self->{_debug};
	  }
	elsif ($state == $HEADER && m!(\d*) site\(s\) sur NOMADE\.FR!)
	  {
	    $self->approximate_result_count($1);
	    $state = $HITS;
	    $langue=$FRANCO;
	    print STDERR "$1 French result\n"  if $self->{_debug};
	  }
	######
	# NEXT URL
	#
	elsif (m{<A HREF="([^\"]*?)"><B>Page suivante ></B></A>})
	  {
	    $self->{_next_url} = new URI::URL($1, $self->{_base_url});
	    if ($self->{_next_url}!~/^http:\/\//) 
		{$self->{_next_url}=$self->{'search_base_url'}.'/'.
		   $self->{_next_url};}		
	    print STDERR "Found next, $1.\n" if $self->{_debug};
	  }

	######
	# HITS PARSING: find each hit
	#
	elsif ($state!=$HEADER) {$buf.=$_."\n";}
    } # Fin du parcours par ligne

    # If French search give no result, other pattern	
    if ((defined $langue) && ($langue==$MONDIAL))
	{	
	  my @l=split(/<dl>/,$buf);
	  foreach my $buf (@l)
	    {
		my ($url, $titre, $desc);
		foreach (split(/\n/, $buf))
		  {
		    if (m!\t{4}<a HREF="(.*?)">(.*)</a>!)
			{ $url = $1; $titre=$2; }
		    elsif (m!^<small>(.*)!) { $desc = $1;}
		    elsif (m!</dl>!)
			{ $hits_found+=$self->create_hit($url,$titre,$desc); }
		  }
	    }	
	}
    # French result
    elsif (defined $langue && $langue==$FRANCO)
	{
	  my @l=split(/<dl>/,$buf);
	  foreach my $buf (@l)
	    {
		my ($url, $titre, $desc);
		foreach (split(/\n/, $buf))
		  {
		    if (m!<b>(\d*)\xa0-</b>\xa0\xa0
			  <a \s target="_blank" \s HREF="(.*?)">
			  .*<b><u>(.*)</u></b>!x)
			{ $url = $2; $titre=$3; }
		    elsif (m!^<small>(.*)<BR></small><small class="taille1"!) 
			{ $desc = $1;}
		    elsif (m!</dl>!)
			{$hits_found+=$self->create_hit($url,$titre,$desc); }
		  }
	    }	
	}
    return $hits_found;
  }

1;

=head1 NAME

WWW::Search::Nomade - class for searching Nomade 

=head1 SYNOPSIS

  use WWW::Search;

  my $oSearch = new WWW::Search('Nomade');

  $oSearch->maximum_to_retrieve(100);

  #$oSearch ->{_debug}=1;

  # Create request
  $oSearch->native_query(WWW::Search::escape_query("cgi"));

  # or Make an international search (on google db)
  $oSearch->native_query(WWW::Search::escape_query("cgi"),
			     { opt => 1 });

  print "I find ", $oSearch->approximate_result_count(),"\n";
  while (my $oResult = $oSearch->next_result())
  { print "Url:", $oResult->url,"\n","Titre:", $oResult->title,"\n"; }

=head1 DESCRIPTION

This class is an Nomade specialization of WWW::Search.
It handles making and interpreting Nomade searches
F<http://www.Nomade.fr>, a french search engine.

This class exports no public interface; all interaction should be done
through WWW::Search objects.

=head1 AUTHOR

C<WWW::Search::Nomade> is written by Alain BARBET,
alian@alianwebserver.com

=cut
