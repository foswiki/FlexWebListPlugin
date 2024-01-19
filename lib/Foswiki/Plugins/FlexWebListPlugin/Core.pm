# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2024 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::FlexWebListPlugin::Core;

use strict;
use warnings;

use Fcntl qw(:flock);
use Encode ();
use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::FlexWebListPlugin::WebFilter ();

use constant TRACE => 0; # toggle me

sub new {
  my $class = shift;

  my $this = bless({@_}, $class);

  #_writeDebug("new FlexWebListPlugin::Core");

  $this->{homeTopic} = Foswiki::Func::getPreferencesValue('HOMETOPIC') 
    || $Foswiki::cfg{HomeTopicName} || 'WebHome';

  $this->{websFileName} = Foswiki::Func::getWorkArea("FlexWebListPlugin")."/webs.txt";
  $this->{lockFileName} = Foswiki::Func::getWorkArea("FlexWebListPlugin")."/webs.lock";
  $this->{mustSave} = 0;

  return $this;
}

sub DESTROY {
  my $this = shift;

  _writeDebug("called DESTROY");
  $this->finish();
  $this->{webList} = undef;
}

sub finish {
  my $this = shift;

  _writeDebug("called finish");
  $this->saveWebList();
}

sub handleFLEXWEBLIST {
  my ($this, $session, $params, $currentTopic, $currentWeb) = @_;

  #_writeDebug("*** called %FLEXWEBLIST{".$params->stringify."}%");
  # extract parameters
  $this->{format} = $params->{_DEFAULT};
  $this->{format} //= $params->{format};
  $this->{format} //= '$web';
  $this->{webs} = $params->{webs} // 'public';
  $this->{header} = $params->{header} // '';
  $this->{footer} = $params->{footer} // '';
  $this->{separator} = $params->{separator} // '';
  $this->{separator} = '' if $this->{separator} eq 'none';
  $this->{subHeader} = $params->{subheader} // $this->{header};
  $this->{subFormat} = $params->{subformat} // $this->{format};
  $this->{subFooter} = $params->{subfooter} // $this->{footer};
  $this->{subSeparator} = $params->{subseparator} // $this->{separator};
  $this->{subSeparator} = '' if $this->{subSeparator} eq 'none';
  $this->{markerFormat} = $params->{markerformat} // $this->{format};
  $this->{selection} = $params->{selection} // '';
  $this->{marker} = $params->{marker} // '';
  $this->{exclude} = $params->{exclude} // '';
  $this->{include} = $params->{include} // '';
  $this->{subWebs} = $params->{subwebs} // 'all';
  $this->{adminwebs} = $params->{adminwebs} // '';
  $this->{ignorecase} = $params->{ignorecase} // 'off';

  if ($this->{adminwebs}) {
    $this->{isAdmin} = _isAdmin();
  } else {
    $this->{isAdmin} = '';
  }

  $this->{selection} =~ s/,/ /g;
  $this->{selection} =~ s/\//./g;
  $this->{selection} = ' '.$this->{selection}.' ';

  $this->{include} =~ s/\//\\\//g;
  _writeDebug("include filter=/^($this->{include})\$/") if $this->{include};
  #_writeDebug("exclude filter=/^($this->{exclude})\$/") if $this->{exclude};

  
  # compute map
  my $theMap = $params->{map} // '';
  $this->{map} = ();
  foreach my $entry (split(/\s*,\s*/, $theMap)) {
    if ($entry =~ /^(.*)=(.*)$/) {
      $this->{map}{$1} = $2;
    }
  }
  
  # compute list
  my %seen;
  my @list = ();
  my @websList = map {my $tmp = $_; $tmp =~ s/^\s+|\s+$//g; $tmp =~ s/\./\//g; $tmp} split(/\s*,\s*/, $this->{webs});
  #_writeDebug("websList=".join(',', @websList));
  my $allWebs = $this->getWebs();

  # collect the list in preserving the given order in webs parameter
  foreach my $aweb (@websList) {
    if ($aweb =~ /^(public|webtemplate|sitemap|user)(current)?$/) {
      $aweb = $1;
      my @webs;
      if (defined $2 && Foswiki::Func::webExists($currentWeb)) {
	push @webs, $currentWeb
      }
      push @webs, keys %{$this->getWebs($aweb)};
      foreach my $bweb (sort @webs) {
	next if $seen{$bweb};
	$seen{$bweb} = 1;
	push @list, $bweb;
      }

    } else {
      next if $seen{$aweb};
      $seen{$aweb} = 1;
      push @list, $aweb if defined $allWebs->{$aweb}; # only add if it exists
    }
  }
  #_writeDebug("list=".join(',', @list));

  # filter webs by setting the 'enabled' flag
  foreach my $aweb (@list) {
    my $web = $allWebs->{$aweb};
    next unless $web;
    $web->{enabled} = 0;
    next if $web->{isSubWeb} && $this->{subWebs} eq 'none';
    if ($this->{ignorecase} eq 'on') {
      next if $this->{exclude} ne '' && $web->{key} =~ /^($this->{exclude})$/i;
      next if $this->{include} ne '' && $web->{key} !~ /^($this->{include})$/i;
    } else {
      next if $this->{exclude} ne '' && $web->{key} =~ /^($this->{exclude})$/;
      next if $this->{include} ne '' && $web->{key} !~ /^($this->{include})$/;
    }
    next if $this->{adminwebs} ne '' && !$this->{isAdmin} &&
      $web->{key} =~ /^($this->{adminwebs})$/;
    $web->{enabled} = 1;
  }

  # format result
  my @result;
  foreach my $aweb (@list) {
    my $web = $allWebs->{$aweb};

    # filter explicite subwebs
    next if $this->{subWebs} !~ /^(all|none|only)$/ && $web->{key} !~ /($this->{subWebs})[\/\.][^\/\.]*$/;

    # start recursion
    my $line = $this->formatWeb($web, $this->{format});
    push @result, $line if $line;
  }

  # reset 'done' flag
  foreach my $aweb (keys %$allWebs) {
    $allWebs->{$aweb}{done} = 0;
  }

  return '' unless @result;

  my $result = join($this->{separator},@result);
  $result = $this->{header}.$result.$this->{footer};
  $result =~ s/\$marker//g;

  _escapeParameter($result);

  #_writeDebug("*** handler done");

  return $result;
}

sub formatWeb {
  my ($this, $web, $format) = @_;

  # check conditions to format this web
  return '' if $web->{done} || !$web->{enabled};
  $web->{done} = 1;

  #_writeDebug("formatWeb($web->{key})");

  my $session = $Foswiki::Plugins::SESSION;

  # format all subwebs recursively
  my $subWebResult = '';
  my @lines;
  foreach my $subWeb (@{$web->{children}}) {
    # filter explicite subwebs
    next if $this->{subWebs} !~ /^(all|none|only)$/ && $subWeb->{key} !~ /($this->{subWebs})[\/\.][^\/]*$/;
    my $line = $this->formatWeb($subWeb, $this->{subFormat}); # recurse
    push @lines, $line if $line;
  }
  if (@lines) {
    my $header = $this->{subHeader};
    my $footer = $this->{subFooter};
    if ($this->{selection} =~ / \Q$web->{key}\E /) {
      $header =~ s/\$marker/$this->{marker}/g;
      $footer =~ s/\$marker/$this->{marker}/g;
    }
    $subWebResult = $this->{subHeader}.join($this->{subSeparator},@lines).$this->{subFooter};
  }

  my $result = '';
  if (!$web->{isSubWeb} && $this->{subWebs} eq 'only') {
    $result = $subWebResult;
  } else {
    if ($this->{selection} =~ / \Q$web->{key}\E /) {
      $format = $this->{markerFormat};
      $format =~ s/\$marker/$this->{marker}/g;
    }
    $result = $format.$subWebResult;
  }
  my $nrSubWebs = @{$web->{children}};
  my $name = $this->{map}{$web->{name}} || $web->{name};

  my $url = '';
  if ($result =~ /\$url/) {
    $url = $session->getScriptUrl(0, 'view', $web->{key}, $this->{homeTopic});
  }

  my $sitemapUseTo = '';
  if ($result =~ /\$sitemapuseto/) {
    $sitemapUseTo = 
      Foswiki::Func::getPreferencesValue('SITEMAPUSETO', $web->{key}) // '';

    $sitemapUseTo =~ s/"/&quot;/g;
    $sitemapUseTo =~ s/<nop>/#nop#/g;
    $sitemapUseTo =~ s/<[^>]*>//g;
    $sitemapUseTo =~ s/#nop#/<nop>/g;
  }

  my $sitemapWhat = '';
  if ($result =~ /\$sitemapwhat/) {
    $sitemapWhat = 
      Foswiki::Func::getPreferencesValue('SITEMAPWHAT', $web->{key}) // '';

    $sitemapWhat =~ s/"/&quot;/g;
    $sitemapWhat =~ s/<nop>/#nop#/g;
    $sitemapWhat =~ s/<[^>]*>//g;
    $sitemapWhat =~ s/#nop#/<nop>/g;
  }

  my $summary = $sitemapWhat // '';
  if ($result =~ /\$summary/) {
    $summary = Foswiki::Func::getPreferencesValue('WEBSUMMARY', $web->{key}) // '';
    $summary =~ s/<nop>//g;
  }

  my $title = $name // '';
  if ($result =~ /\$title/) {
    $title = Foswiki::Func::getTopicTitle($web->{key}, $this->{homeTopic});
    $title = $name if $title eq $this->{homeTopic};
  }

  my $color = '';
  if ($result =~ /\$color/) {
    $color =
      Foswiki::Func::getPreferencesValue('WEBBGCOLOR', $web->{key}) // '';
  }

  $result =~ s/\$parent/$web->{parentName}/g;
  $result =~ s/\$name/$name/g;
  $result =~ s/\$title/$title/g;
  $result =~ s/\$origname/$web->{name}/g;
  $result =~ s/\$qname/"$web->{key}"/g;# historical
  $result =~ s/\$web/$web->{key}/g;
  $result =~ s/\$depth/$web->{depth}/g;
  $result =~ s/\$indent\((.+?)\)/$1 x $web->{depth}/ge;
  $result =~ s/\$indent/'   ' x $web->{depth}/ge;
  $result =~ s/\$nrsubwebs/$nrSubWebs/g;
  $result =~ s/\$url/$url/g;
  $result =~ s/\$sitemapuseto/$sitemapUseTo/g;
  $result =~ s/\$sitemapwhat/$sitemapWhat/g;
  $result =~ s/\$summary/$summary/g;
  $result =~ s/\$color/$color/g;

  #_writeDebug("result=$result");
  #_writeDebug("done formatWeb($web->{key})");

  return $result;
}

sub getWebIterator {
  my ($this, $filter) = @_;

  my @webs = $this->getListOfWebs($filter);
  return Foswiki::ListIterator->new(\@webs);
}

# get a hash of all webs, each web points to its subwebs, each subweb points
# to its parent
sub getWebs {
  my ($this, $filter) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  $filter ||= '';

  #_writeDebug("called getWebs($filter)");

  # lookup cache
  my $wit = $this->getWebIterator($filter);

  my @webs = ();
  if ($filter) {
    $filter = 'user,public,allowed' if $filter eq 'public';
    $filter = 'user,sitemap,allowed' if $filter eq 'sitemap';
    $filter = 'template,allowed' if $filter eq 'webtemplate';

    my $filter = Foswiki::Plugins::FlexWebListPlugin::WebFilter->new($filter);

    while ($wit->hasNext()) {
      my $w = '';
      $w .= '.' if $w;
      $w .= $wit->next();
      push @webs, $w if $filter->ok($session, $w);
    }
  } else {
    @webs = $wit->all();
  }

  my $webs = $this->hashWebs(@webs);

  #_writeDebug("result=".join(',',@webs));
  return $webs;
}

# convert a flat list of webs to a structured parent-child structure;
# the returned hash contains elements of the form
# {
#   key => the full webname (e.g. Main.Foo.Bar)
#   name => the tail of the webname (e.g. Bar)
#   isSubWeb => 1 if the web is a subweb, 0 if it is a top-level web
#   parentName => only defined for subwebs
#   parent => pointer to parent web structure
#   children => list of pointers to subwebs
# }
sub hashWebs {
  my $this = shift;
  my @webs = @_;

  #_writeDebug("hashWebs(".join(',', sort @webs));

  my %webs;
  # collect all webs
  foreach my $key (@webs) {
    $webs{$key}{key} = $key;
    if ($key =~ /^(.*)[\/\.](.*?)$/) {
      $webs{$key}{isSubWeb} = 1;
      $webs{$key}{parentName} = $1;
      $webs{$key}{name} = $2;
    } else {
      $webs{$key}{name} = $key;
      $webs{$key}{isSubWeb} = 0;
      $webs{$key}{parentName} = '';
    }
    $webs{$key}{depth} = ($key =~ tr/\///) || ($key =~ tr/\.//);
  }

  # establish parent-child relation
  foreach my $key (@webs) {
    my $parentName = $webs{$key}{parentName};
    if ($parentName) {
      $webs{$key}{parent} = $webs{$parentName};
      push @{$webs{$parentName}{children}}, $webs{$key}
        if defined $webs{$parentName};
    }
  }
  #_writeDebug("keys=".join(',',sort keys %webs));

  return \%webs;
}

sub getListOfWebs {
  my ($this, $filter, $web) = @_;

  #_writeDebug("called getListOfWebs(".($filter//'undef').",".($web//'undef').")");

  my @result = $this->readWebList();
  @result = grep {/^($web)[\/\.]/} @result if defined $web;

  if (defined $filter) {
    my $f = Foswiki::Plugins::FlexWebListPlugin::WebFilter->new($filter);
    my $session = $Foswiki::Plugins::SESSION;
    @result = grep {$f->ok($session, $_)} @result;
  }

  return @result;
}

sub readWebList {
  my $this = shift;

  my $file = $this->{websFileName};
  my $modified = _modificationTime($file);

  if (!$this->{webList} || $modified > $this->{loadTime}) {
    _writeDebug("... reading from $file");

    if (-e $file) {
      $this->lock(LOCK_SH);
      my $data = Foswiki::Func::readFile($file);
      $data = Encode::decode_utf8($data);
      $this->unlock();
      @{$this->{webList}} = split("\n", $data) if $data;
    } 

    unless ($this->{webList}) {
      _writeDebug("... calling store for webs");
      @{$this->{webList}} = map {_normalizeWebName($_)} Foswiki::Func::origGetListOfWebs();
      $this->{mustSave} = 1;
    }

    $this->{loadTime} = time();
    _writeDebug("... ".scalar(@{$this->{webList}})." webs in cache");
  }

  return @{$this->{webList}};
}

sub updateWeb {
  my ($this, $web) = @_;

  _writeDebug("called udateWeb($web)");
  return $this->addWeb($web) if Foswiki::Func::webExists($web);
  return $this->removeWeb($web);
}

sub removeWeb {
  my ($this, $web) = @_;

  $web = _normalizeWebName($web);
  _writeDebug("called removeWeb($web)");

  my %knownWebs = map {_normalizeWebName($_) => 1} $this->readWebList();
  if ($knownWebs{$web}) {
    delete $knownWebs{$web};
    @{$this->{webList}} = keys %knownWebs;
    $this->{mustSave} = 1;
  }
}

sub addWeb {
  my ($this, $web) = @_;

  $web = _normalizeWebName($web);
  _writeDebug("called addWeb($web)");

  my %knownWebs = map {_normalizeWebName($_) => 1} $this->readWebList();
  unless ($knownWebs{$web}) {
    $knownWebs{$web} = 1;
    @{$this->{webList}} = keys %knownWebs;
    $this->{mustSave} = 1;
  }
}

sub saveWebList {
  my $this = shift;

  return unless $this->{mustSave};
  $this->{mustSave} = 0;

  _writeDebug("saveWebList()");

  $this->lock();
  _writeDebug("... ".scalar(@{$this->{webList}})." webs in cache");
  my $data = join("\n", sort @{$this->{webList}})."\n";
  $data = Encode::encode_utf8($data);
  Foswiki::Func::saveFile($this->{websFileName}, $data);

  $this->{loadTime} = time(); #update to prevent reloading it

  $this->unlock();
}

sub clearCache {
  my $this = shift;

  _writeDebug("called clearCache");

  $this->lock();
  $this->{webList} = undef;
  unlink $this->{websFileName} if -e $this->{websFileName};
  $this->unlock();
}

sub lock {
  my ($this, $mode) = @_;

  $mode ||= LOCK_EX;

  _writeDebug("called lock");
  unless (defined $this->{lockFile}) {
    open($this->{lockFile}, ">", $this->{lockFileName}) or die "can't create lock file $this->{lockFileName}";
  }

  flock($this->{lockFile}, $mode); 
}

sub unlock {
  my $this = shift;

  _writeDebug("called unlock");

  if (defined $this->{lockFile}) {
    flock($this->{lockFile}, LOCK_UN);
    close($this->{lockFile});
    $this->{lockFile} = undef;
    unlink $this->{lockFileName} if -e $this->{lockFileName};
  }

}

sub _modificationTime {
  my $filename = shift;

  my @stat = stat($filename);
  return $stat[9] || $stat[10] || 0;
}

sub _isAdmin { 

  if ($Foswiki::Plugins::VERSION >= 1.2) {
    return Foswiki::Func::isAnAdmin();
  }

  my $user = $Foswiki::Plugins::SESSION->{user};
  if ($user) {
    return $user->isAdmin();
  }

  # do we need to support more legacy apis

  return 0;
}

sub _escapeParameter {
  return '' unless $_[0];

  $_[0] =~ s/\$perce?nt/%/g;
  $_[0] =~ s/\$nop//g;
  $_[0] =~ s/\$n/\n/g;
  $_[0] =~ s/\$dollar/\$/g;
}

sub _normalizeWebName {
  my $web = shift;

  $web =~ s/\//\./g;

  return $web;
}

sub _writeDebug {
  print STDERR '- FlexWebListPlugin::Core - '.$_[0]."\n" if TRACE;
}

1;
