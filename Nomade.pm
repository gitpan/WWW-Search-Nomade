#!/usr/local/bin/perl -w

#
# Nomade.pm
# by Alain Barbet
# Copyright (C) 2000
# $Id: Nomade.pm,v 0.3 2000/10/25 11:07:14 alian Exp $
#

package WWW::Search::Nomade;

=head1 NAME

WWW::Search::Nomade - class for searching Nomade 


=head1 SYNOPSIS

    require WWW::Search;
    $search = new WWW::Search('Nomade');


=head1 DESCRIPTION

This class is an Nomade specialization of WWW::Search.
It handles making and interpreting Nomade searches
F<http://www.Nomade.fr>, a french search engine.

This class exports no public interface; all interaction should be done
through WWW::Search objects.

=head1 USAGE EXAMPLE

  use WWW::Search;

  my $oSearch = new WWW::Search('Nomade');
  $oSearch->maximum_to_retrieve(100);

  #$oSearch ->{_debug}=1;

  my $sQuery = WWW::Search::escape_query("cgi");
  $oSearch->gui_query($sQuery);

  while (my $oResult = $oSearch->next_result())
  {
        print $oResult->url,"\t",$oResult->title,"\n";
  }


=head1 AUTHOR

C<WWW::Search::Nomade> is written by Alain BARBET,
alian@alianwebserver.com

=cut

#####################################################################

require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
@ISA = qw(WWW::Search Exporter);
$VERSION = '0.3';

use Carp ();
#use strict "vars";
use WWW::Search(generic_option);
require WWW::SearchResult;

# private
sub native_setup_search
	{
    	my($self, $native_query, $native_options_ref) = @_;
    	$self->user_agent('alian');
    	$self->{_next_to_retrieve} = 0;
  	$self->{'search_base_url'} = 'http://rechercher.nomade.fr';  	
	if (!defined($self->{_options})) {
	$self->{_options} = { 
	    's' 	=> $native_query,
	    'search_url' => $self->{'search_base_url'}.'/recherche.asp'
        };}
    	my($options_ref) = $self->{_options};
    	if (defined($native_options_ref)) 
    		{
		# Copy in new options.
		foreach (keys %$native_options_ref) {$options_ref->{$_} = $native_options_ref->{$_};}
    		}
    	# Process the options.
    	# (Now in sorted order for consistency regarless of hash ordering.)
    	my($options) = '';
    	foreach (sort keys %$options_ref) 
    		{
		# printf STDERR "option: $_ is " . $options_ref->{$_} . "\n";
		next if (generic_option($_));
		$options .= $_ . '=' . $options_ref->{$_} . '&' if (defined $options_ref->{$_});
    		}

    	# Finally figure out the url.
    	$self->{_base_url} = $self->{_next_url} = $self->{_options}{'search_url'} ."?" . $options;
    	print STDERR $self->{_base_url} . "\n" if ($self->{_debug});	
	}

# private
sub create_hit
	{
	my ($self,$url,$titre,$description)=@_;
	my $hit = new WWW::SearchResult;
	$hit->add_url($url);
	$hit->title($titre);
	$hit->description($description);
	push(@{$self->{cache}},$hit);
	return 1;
	}

# private
sub native_retrieve_some
	{
 	my ($self) = @_;      
	my($hits_found) = 0;
	my ($buf,$langue);

 	#fast exit if already done
	return undef if (!defined($self->{_next_url}));    
	print STDERR "WWW::Search::Nomade::native_retrieve_some: fetching " . $self->{_next_url} . "\n" if ($self->{_debug});
	my($response) = $self->http_request('GET', $self->{_next_url});
	$self->{response} = $response;
	print STDERR "WWW::Search::Nomade GET  $self->{_next_url} return ",$response->code,"\n"  if ($self->{_debug});
  	if (!$response->is_success) {return undef;};
	$self->{_next_url} = undef; 

    	# parse the output
    	my($HEADER, $HITS, $INHIT, $INLINK, $TRAILER, $POST_NEXT, $FRANCO, $MONDIAL,$PREMIUM) = (1..10);  # order matters
    	my($state) = ($HEADER);    	
    	my($raw) = '';
    	foreach ($self->split_lines($response->content())) {#print $_,"\n";
        next if m@^$@; # short circuit for blank lines
	######
	# HEADER PARSING: find the number of hits
	#
	if ($state == $HEADER && /Il n'existe pas de document r&eacute;pondant &agrave; votre requ&ecirc;te/) 
		{
	    	$self->approximate_result_count(0);
	    	$state = $TRAILER;
	    	print STDERR "No result\n"  if ($self->{_debug});
		}
	elsif ($state == $HEADER && m!<B>&nbsp;&nbsp;&nbsp;(\d+) sites</B> <B>pour ".*"</B><BR>!) 
		{
	    	$self->approximate_result_count($1);
	    	$state = $HITS;
	    	$langue=$FRANCO;
	    	print STDERR "$1 French result\n"  if $self->{_debug};
		}
	elsif ($state == $HEADER && m!&nbsp;&nbsp;<SMALL><B>(\d+) pages pour .*</b><BR>!)
		{
	    	$self->approximate_result_count($1);
	    	$state = $HITS;
	    	$langue=$MONDIAL;
	    	print STDERR "$1 English result\n"  if $self->{_debug};
		}
	elsif ($state == $HEADER && m!<B>&nbsp;&nbsp;&nbsp;Plus de 200 sites!)
		{
		$self->approximate_result_count(200);
		$state = $HITS;
	    	$langue=$FRANCO;
	    	print STDERR "More than 200 result.Premium\n"  if $self->{_debug};
		}

	######
	# NEXT URL
	#
	elsif (m{<!-- début du paging -->.*<A HREF="(.*?)"><B>Page suivante&nbsp></B></A>})
		{
		$self->{_next_url} = new URI::URL($1, $self->{_base_url});
		if ($self->{_next_url}!~/^http:\/\//) 
			{$self->{_next_url}=$self->{'search_base_url'}.'/'.$self->{_next_url};}		
		print STDERR "Found next, $1.\n" if $self->{_debug};
		}
	elsif (m{<!-- début du paging -->.*<A HREF="(.*)"><B>Tous les sites pour})
		{
		$self->{_next_url} = new URI::URL($1, $self->{_base_url});
		if ($self->{_next_url}!~/^http:\/\//) 
			{$self->{_next_url}=$self->{'search_base_url'}.'/'.$self->{_next_url};}		
		print STDERR "Found next, $1.\n" if $self->{_debug};
		}
	######
	# HITS PARSING: find each hit
	#
	elsif ($state!=$HEADER) {$buf.=$_."\n";}
	}

	# If French search give no result, other pattern	
	if ((defined $langue) && ($langue==$MONDIAL))
		{	
		my @l=split(/\n/,$buf);
		foreach(@l)
			{
			if (m!<A HREF="(.*?)"><B><LI></B><P><B> (.*?)</B></A>&nbsp;&nbsp;<A HREF=".*</A><BR>(.*?)<BR>!) 
				{
				$hits_found+=$self->create_hit($1,$2,$3);
				print STDERR "Found $1\nTitle:$2\nDescription:$3\n"  if $self->{_debug};
				}
			}
		}
	# French result
	elsif (defined $langue && $langue==$FRANCO)
		{
		my @l=split(/<DL>/,$buf);
		foreach (@l)
			{
			if (m!<DT>&nbsp;&nbsp;&nbsp;<A HREF="(.*?)"><B>\d+. (.*?)</B></A>.*<DD>(.*?)<BR>!) 
				{
				$hits_found+=$self->create_hit($1,$2,$3);
				print STDERR "Found $1\nTitle:$2\nDescription:$3\n"  if ($self->{_debug});
				}
			}	
		}
	return $hits_found;
	}

1;
